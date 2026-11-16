class CONTRACTS
create make
feature
    make
        local f, report: PLAIN_TEXT_FILE; args: ARRAYED_LIST [VALUE]
            op: STRING; count, i: INTEGER; v, a, b: VALUE
        do
            create f.make_open_read ("contract-input.txt")
            f.read_line; op := f.last_string.twin
            f.read_line; count := f.last_string.to_integer
            create args.make (count)
            from i := 1 until i > count loop
                create v.read_from (f); args.extend (v); i := i + 1
            end
            f.close
            expect (not args.is_empty, "An operation needs operands.")
            across args as arg loop expect (arg.valid, "A value has an invalid shape, size, or non-finite number.") end
            a := args.first; b := args.last
            if op.is_equal ("array") then
                expect (a.shape.count < 2, "Arrays have at most two dimensions.")
                across args as arg loop expect (a.same_shape (arg), "Matrix rows must have equal lengths.") end
            elseif op.is_equal ("dot") then
                expect (a.shape.count = 1 and b.shape.count = 1 and a.same_shape (b), "dot needs vectors of equal length.")
            elseif op.is_equal ("matmul") then
                expect (a.shape.count = 2 and b.shape.count = 2, "matmul needs two matrices.")
                expect (a.shape.last = b.shape.first, "Matrix inner dimensions must match.")
            elseif op.is_equal ("det") then
                expect (a.shape.count = 2, "det needs a square matrix.")
                expect (a.shape.first = a.shape.last and a.shape.first <= 6, "det needs a square matrix of size 1 to 6.")
            elseif op.is_equal ("transpose") then
                expect (a.shape.count = 2, "transpose needs a matrix.")
            elseif op.is_equal ("sum") or op.is_equal ("mean") or op.is_equal ("min") or op.is_equal ("max") then
                if not a.scalar then expect (args.count = 1, "An array summary takes exactly one array.") end
            elseif op.is_equal ("add") or op.is_equal ("sub") or op.is_equal ("mul") or op.is_equal ("div") then
                expect (a.scalar or b.scalar or a.same_shape (b), "Array dimensions must match, or one operand must be a scalar.")
            end
            if op.is_equal ("div") or op.is_equal ("recip") then
                across b.items as number loop expect (number /= 0, "Division by zero is undefined.") end
            elseif op.is_equal ("sqrt") then
                across a.items as number loop expect (number >= 0, "Square root needs a non-negative argument.") end
            elseif op.is_equal ("fact") then
                across a.items as number loop
                    expect (number >= 0 and number <= 170 and number = number.floor_real_64, "Factorial needs an integer from 0 to 170.")
                end
            end
            create report.make_open_write ("contracts.txt")
            report.put_string ("Passed: " + op + "; finite values, valid shapes, enabled Eiffel preconditions and postconditions.")
            report.close
        end
    expect (condition: BOOLEAN; message: STRING)
        local f: PLAIN_TEXT_FILE
        do
            if not condition then
                create f.make_open_write ("error.txt"); f.put_string (message); f.close
            end
            require_true (condition)
        ensure
            condition_met: condition
        end
    require_true (condition: BOOLEAN)
        require
            contract_satisfied: condition
        do
        ensure
            contract_still_satisfied: condition
        end
end
