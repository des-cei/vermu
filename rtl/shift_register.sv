module shift_register #(
    parameter int  CYCLES =    4,                  // profundidad del shift
    parameter type data_t = logic     // tipo del dato acompañante
)(
    input  logic  clk_i,
    input  logic  rst_ni,        // reset asíncrono, activo a nivel bajo
    input  logic  en_i,          // habilita el desplazamiento (opcional)

    input  logic  bit_i,
    input  data_t data_i,

    output logic  bit_o,
    output data_t data_o
);

    generate
        if (CYCLES == 0) begin : g_no_delay
            assign bit_o  = bit_i;
            assign data_o = data_i;
        end else begin : g_delay

            logic  [CYCLES-1:0] bit_shift_q;
            data_t               data_shift_q [CYCLES-1:0];

            always_ff @(posedge clk_i or negedge rst_ni) begin
                if (!rst_ni) begin
                    bit_shift_q <= '0;
                    for (int i = 0; i < CYCLES; i++)
                        data_shift_q[i] <= '0;
                end else if (en_i) begin
                    bit_shift_q <= {bit_shift_q[CYCLES-2:0], bit_i};

                    data_shift_q[0] <= data_i;
                    for (int i = 1; i < CYCLES; i++)
                        data_shift_q[i] <= data_shift_q[i-1];
                end
            end

            assign bit_o  = bit_shift_q[CYCLES-1];
            assign data_o = data_shift_q[CYCLES-1];

        end
    endgenerate

endmodule