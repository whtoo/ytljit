module YTLJit

=begin
  Stack layout (on stack frame)


Hi     |  |Argn                   |   |
       |  |   :                   |   |
       |  |Arg3(exception status) |   |
       |  |Arg2(block pointer)    |   |
       |  |Arg1(parent frame)     |  -+
       |  |Arg0(self)             |
       |  |Return Address         |
       +- |old bp                 | <-+
          |old bp on stack        |  -+
    EBP-> |Local Vars1            |   
          |                       |   
          |                       |   
          |Local Varsn            |   
          |Pointer to Env         |   
   SP ->  |                       |
          |                       |
LO        


  Stack layout (on heap frame)


Hi     |  |Arg0(self)             |   |
       |  |Arg1(parent frame)     |  -+
       |  |Arg2(block pointer)    |
       |  |Arg3(exception status) |
       |  |   :                   |
       |  |Arg n                  |
       |  |Return Address         |
       +- |old bp                 |  <---+
          |Pointer to Env         |  -+  |
   SP ->  |                       |   |  |
LO        |                       |   |  |
                                      |  |
                                      |  |
       +- |                       |   |  |
       |  |free func              |   |  |
       |  |mark func              |   |  |
       |  |T_DATA                 | <-+  |                                      
       |                                 |
       |                                 |
       |  |Arg n                  |      |
       |  |   :                   |      |
       |  |Arg3(exception status) |      |
       |  |Arg2(block pointer)    |      |
       |  |Arg1(parent frame)     |      |
       |  |Arg0(self)             |      |   
       |  |Not used(reserved)     |      |
       |  |Not used(reserved)     |      |
       |  |old bp on stack        | -----+
    EBP-> |Local Vars1            |   
       |  |                       |   
       |  |                       |   
       +->|Local Varsn            |   

  enter procedure
    push EBP
    SP -> EBP
    allocate frame (stack or heap)    
    Copy arguments if allocate frame on heap
    store EBP on the top of frame
    Address of top of frame -> EBP
 
  leave procedure
    Dereference of EBP -> ESP
    pop EBP
    ret

=end

  module VM
    class Context
      include AbsArch
      def initialize
        @code_space = nil
        @assembler = nil
        
        # RETR(EAX, RAX) or RETFR(STO, XM0) or Immdiage object
        @ret_reg = RETR
        @used_reg = {}
      end

      attr_accessor :code_space
      attr_accessor :assembler
      attr_accessor :ret_reg
      attr          :used_reg

      def add_code_space(cs)
        @code_space = cs
        @assembler = Assembler.new(cs)
      end
    end

    module Node
      module MethodTopCodeGen
        include AbsArch
        
        def gen_method_prologue(context)
          asm = context.assembler

          asm.with_retry do
            # Make linkage of frame pointer
            asm.push(BPR)
            asm.mov(BPR, SPR)
            asm.push(BPR)
            asm.mov(BPR, SPR)
          end
            
          context
        end
      end

      module MethodEndCodeGen
        include AbsArch

        def gen_method_epilogue(context)
          asm = context.assembler

          # Make linkage of frame pointer
          asm.with_retry do
            asm.mov(SPR, BPR)
            asm.pop(BPR)
            asm.mov(SPR, BPR)
            asm.pop(BPR)
          end

          context
        end
      end

      module IfNodeCodeGen
        include AbsArch

        def unify_retreg_tpart(tretr, eretr, asm)
        end

        def unify_retreg_epart(tretr, eretr, asm)
        end

        def unify_retreg_cont(tretr, eretr, asm)
        end
      end
      
      module LocalVarNodeCodeGen
        include AbsArch

        def gen_pursue_parent_function(context, depth)
          asm = context.assembler
          if depth != 0 then
            context.used_reg[TMPR2] = true
            asm.mov(TMPR2, BPR)
            depth.times do 
              asm.mov(TMPR2, frame_info.offset_arg(0, TMPR2))
            end
            context.ret_reg = TMPR2
          else
            context.ret_reg = BPR
          end
          context
        end
      end
    end

    module SendNodeCodeGen
      include AbsArch
      
      def gen_make_argv(context)
        casm = context.assembler
        rarg = @arguments[2..-1]

        # adjust stack pointer
        casm.with_retry do
          casm.sub(SPR, rarg.size * Type::MACHINE_WORD.size)
        end
        
        # make argv
        rarg.each_with_index do |arg, i|
          context = arg.compile(context)
          casm = context.assembler
          dst = OpIndirect.new(SPR, i * Type::MACHINE_WORD.size)
          casm.with_retry do
            casm.mov(TMPR, context.ret_reg)
            casm.mov(dst, TMPR)
          end
        end

        # Save Stack Pointer
        casm.with_retry do
          casm.mov(TMPR2, SPR)
        end

        # stack, generate call ...
        context = yield(context, rarg)

        # adjust stack
        casm.with_retry do
          casm.add(SPR, rarg.size * Type::MACHINE_WORD.size)
        end

        context
      end

      def gen_call(context, fnc)
        casm = context.assembler
        casm.with_retry do 
          casm.call_with_arg(fnc, @arguments.size)
        end
        off = casm.offset
        @var_return_address = casm.output_stream.var_base_address(off)
        
        context
      end
    end
  end
end
