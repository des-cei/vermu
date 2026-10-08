    // Copyright 2026 CEIMM-UPM
    // Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
    // SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
    // Ane Corral (ane.corral@upm.es)

    // -----------------------------------------------------------------------------
    // obi_mem_model : sparse, byte-addressable memory behind one or more OBI ports
    //
    //  * Byte-granular storage (associative array) -> any address, no size limit.
    //  * Honours byte-enables on writes; reads return the whole bus word.
    //  * Every request is answered with an rvalid (also writes), in order.
    //  * Optional back-pressure (GNT_STALL_PCT) and response latency / jitter to
    //    stress the DUT's handshaking.
    //  * Records every granted access (access_log) so a test can check *how* the
    //    DUT used the bus, not only the final memory content.
    //  * Flags reads of never-written bytes (uninit_reads): a cheap over-read detector.
    //
    // Backdoor API (call hierarchically from the testbench):
    //   clear_mem(), write8(), read8(), fill(), fill_incr(), clear_log(),
    //   count_reads(), count_writes(), reads_within(), writes_within()
    // -----------------------------------------------------------------------------

    module obi_mem_model
    import obi_pkg::*;
    #(
    parameter int unsigned PORTS          = 1,
    parameter int unsigned DATA_W         = 32,
    parameter int unsigned GNT_STALL_PCT  = 0,    // % of cycles in which gnt is withheld
    parameter int unsigned RSP_LATENCY    = 1,    // min cycles gnt -> rvalid (>=1)
    parameter int unsigned RSP_EXTRA_MAX  = 0,    // random extra response delay 0..N
    parameter logic [7:0]  UNINIT_BYTE    = 8'hDD,
    parameter bit          VERBOSE        = 1'b0
    ) (
    input  logic                    clk_i,
    input  logic                    rst_ni,
    input  obi_req_t  [PORTS-1:0]   req_i,
    output obi_resp_t [PORTS-1:0]   resp_o
    );

    localparam int unsigned BYTES = DATA_W / 8;

    /////////////
    // Storage //
    /////////////
    
    logic [7:0] mem [bit [31:0]];

    typedef struct {
        int unsigned       port;
        time               t;
        bit [31:0]         addr;
        bit                we;
        bit [BYTES-1:0]    be;
        bit [DATA_W-1:0]   wdata;
    } access_t;

    access_t     access_log [$];
    int unsigned uninit_reads = 0;

    typedef struct {
        bit [DATA_W-1:0]   data;
        longint unsigned   due;
    } rsp_t;

    rsp_t                 rsp_q      [PORTS][$];
    longint unsigned      last_due   [PORTS];
    longint unsigned      cyc = 0;

    logic [PORTS-1:0]     gnt_ok_q;
    logic [PORTS-1:0]     rvalid_q;
    logic [DATA_W-1:0]    rdata_q [PORTS];

    //////////////
    // OBI side //
    //////////////

    always_comb begin
        for (int p = 0; p < PORTS; p++) begin
            resp_o[p]        = '0;
            resp_o[p].gnt    = req_i[p].req && gnt_ok_q[p];
            resp_o[p].rvalid = rvalid_q[p];
            resp_o[p].rdata  = rdata_q[p];
        end
    end

    always_ff @(posedge clk_i) begin
        cyc = cyc + 1;
        if (!rst_ni) begin
            gnt_ok_q <= '1;
            rvalid_q <= '0;
            for (int p = 0; p < PORTS; p++) begin
                rdata_q[p]  <= '0;
                last_due[p]  = 0;
                rsp_q[p].delete();
            end
        end else begin
            for (int p = 0; p < PORTS; p++) begin
                bit [31:0]       base;
                bit [DATA_W-1:0] rd;
                rsp_t            r;
                access_t         a;

                gnt_ok_q[p] <= ($urandom_range(99) >= GNT_STALL_PCT);
                rvalid_q[p] <= 1'b0;

                // granted request: perform the access 
                if (req_i[p].req && gnt_ok_q[p]) begin
                    base = req_i[p].addr & ~32'(BYTES - 1);
                    rd   = '0;
                    a.port  = p;
                    a.t     = $time;
                    a.addr  = req_i[p].addr; a.we  = req_i[p].we;
                    a.be    = req_i[p].be; a.wdata = req_i[p].wdata;
                    access_log.push_back(a);

                    if (req_i[p].we) begin
                        for (int j = 0; j < BYTES; j++)
                            if (req_i[p].be[j]) mem[base + j] = req_i[p].wdata[8*j +: 8];
                    end else begin
                        for (int j = 0; j < BYTES; j++) begin
                            if (mem.exists(base + j))
                                rd[8*j +: 8] = mem[base + j];
                            else begin
                                rd[8*j +: 8] = UNINIT_BYTE;
                                if (req_i[p].be[j]) begin
                                    uninit_reads++;
                                    $warning("[%0t] OBI MEM: port %0d read of uninitialised byte 0x%08h",
                                            $time, p, base + j);
                                end
                            end
                        end
                    end

                    if (VERBOSE)
                        $display("[%0t] OBI MEM p%0d %s addr=%08h be=%b wdata=%08h rdata=%08h",
                                $time, p, req_i[p].we ? "WR" : "RD", req_i[p].addr,
                                req_i[p].be, req_i[p].wdata, rd);

                    // in-order response, never earlier than the previous one
                    r.data = rd;
                    r.due  = cyc + (RSP_LATENCY - 1) +
                            ((RSP_EXTRA_MAX > 0) ? $urandom_range(RSP_EXTRA_MAX) : 0);
                    if (r.due < last_due[p]) r.due = last_due[p];
                    last_due[p] = r.due;
                    rsp_q[p].push_back(r);
                end

                // ---- response channel
                if (rsp_q[p].size() > 0 && rsp_q[p][0].due <= cyc) begin
                    rvalid_q[p] <= 1'b1;
                    rdata_q[p]  <= rsp_q[p][0].data;
                    void'(rsp_q[p].pop_front());
                end
            end
        end
    end

    //////////////////
    // backdoor API //
    //////////////////

    function automatic void clear_mem();
        mem.delete();
        access_log.delete();
        uninit_reads = 0;
    endfunction

    function automatic void clear_log();
        access_log.delete();
        uninit_reads = 0;
    endfunction

    function automatic void write8(input bit [31:0] addr, input logic [7:0] data);
        mem[addr] = data;
    endfunction

    function automatic logic [7:0] read8(input bit [31:0] addr);
        return mem.exists(addr) ? mem[addr] : UNINIT_BYTE;
    endfunction

    function automatic void fill(input bit [31:0] addr, input int unsigned n,
                                input logic [7:0] value);
        for (int unsigned i = 0; i < n; i++) mem[addr + i] = value;
    endfunction

    // byte i = start + i (mod 256): every byte of a window is distinguishable
    function automatic void fill_incr(input bit [31:0] addr, input int unsigned n,
                                        input logic [7:0] start);
        for (int unsigned i = 0; i < n; i++) mem[addr + i] = 8'(start + i);
    endfunction

    function automatic int unsigned count_reads();
        int unsigned n = 0;
        foreach (access_log[i]) if (!access_log[i].we) n++;
        return n;
    endfunction

    function automatic int unsigned count_writes();
        int unsigned n = 0;
        foreach (access_log[i]) if (access_log[i].we) n++;
        return n;
    endfunction

    // Every logged read lies inside the BUS WORDS covering [lo, hi)
    function automatic bit reads_within(input bit [31:0] lo, input bit [31:0] hi);
        foreach (access_log[i])
        if (!access_log[i].we &&
            ((access_log[i].addr | (BYTES - 1)) < lo || access_log[i].addr >= hi))
            return 1'b0;
        return 1'b1;
    endfunction

    // Every byte written (be set) lies inside [lo, hi)
    function automatic bit writes_within(input bit [31:0] lo, input bit [31:0] hi);
        foreach (access_log[i])
        if (access_log[i].we)
            for (int j = 0; j < BYTES; j++)
            if (access_log[i].be[j]) begin
                bit [31:0] a = (access_log[i].addr & ~32'(BYTES - 1)) + j;
                if (a < lo || a >= hi) return 1'b0;
            end
        return 1'b1;
    endfunction

endmodule