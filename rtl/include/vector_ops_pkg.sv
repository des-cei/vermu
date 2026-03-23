// SIMD Lane Vector Intructions

package vector_ops_pkg;

    typedef enum logic [5:0] {
        NOP,
        //Arithmetic and (bitwise) logic instructions
        VADD, VSUB, VRSUB, VAND, VOR, VXOR,		 
        //VWADDU,VWSUBU, VWADD, VWSUB, 
    	
        // Integer add-with-carry and subtract-with-borrow carry-out instructions
        VMADC,//VADC, VMADC, VMMV, VSBC, VMSBC,   VMADC,
        //Shifts instructions
        VSLL, VSRL, VSRA,
        
        //Vector Narrowing Integer Right Shift instructions
        //VNSRL, VNSRA,
        
        //Mul/Mul-add instruction
        VMUL,  VMULH, VMULHU, VMULHSU, VMACC, VNMSAC, VMADD, VNMSUB,
    
        //Vector Widening Integer Multiply Instructions
        //VWMUL, VWMULU, VWMULSU	  
        
        //Vector Widening Integer Multiply-Add Instructions
        //VWMACCU, VWMACC, VWMACCSU, VWMACCUS,
        
        //Div instruction
        //VDIVU, VDIV, VREMU,VREM	
        
        //Min/max instruction
        VMINU, VMIN, VMAXU, VMAX,
        
        //Integer comparison  instructions
        VMSEQ, VMSNE, VMSLTU, VMSLT, VMSLEU, VMSLE, VMSGTU, VMSGT, VMSGEU, VMSGE,
        
        //Zero- sign- extend  --> Not necessary, EEW always > SEW
        //VZEXT, VSEXT
        
        //Merge and move  instruction      
        VMV, //VMERGE, 	

        //Reduction 
        VREDSUM
    } op_e; 
 	 
 
endpackage
