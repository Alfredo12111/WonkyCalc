USING: accessors arrays combinators continuations io.encodings.utf8
io.files kernel locals math math.functions math.parser sequences
splitting strings vectors ;
IN: wonkycalc

:: apply-op ( name args -- result )
    args first :> a
    args last :> b
    name {
        { "add" [ a b + ] } { "sub" [ a b - ] }
        { "mul" [ a b * ] } { "div" [ a b / ] }
        { "pow" [ a b ^ ] } { "neg" [ a neg ] }
        { "percent" [ a 100 / ] } { "abs" [ a abs ] }
        { "sqrt" [ a sqrt ] } { "recip" [ 1 a / ] }
        { "sum" [ args sum ] } { "mean" [ args sum args length / ] }
        { "min" [ args infimum ] } { "max" [ args supremum ] }
        { "floor" [ a floor ] } { "ceil" [ a ceiling ] }
        { "unit_m" [ a ] } { "unit_s" [ a ] }
        { "unit_seconds" [ a ] } { "unit_kg" [ a ] }
        { "unit_cm" [ a 100 / ] } { "unit_km" [ a 1000 * ] }
        { "unit_ms" [ a 1000 / ] } { "unit_g" [ a 1000 / ] }
        [ "Unsupported operation: " prepend throw ]
    } case ;

:: check-expression ( -- )
    V{ } clone :> stack
    "tokens.txt" utf8 file-lines [| line |
        line " " split :> parts
        parts first {
            { "N" [ parts second string>number dup [ stack push ] [ drop "Invalid number" throw ] if ] }
            { "C" [ parts second "ans" = [ "context.txt" utf8 file-lines second string>number stack push ] [ "Constants pi, tau and e are outside this independent check." throw ] if ] }
            { "F" [
                parts third string>number :> count
                stack length count - :> start
                start stack length stack subseq >array :> args
                start stack set-length
                parts second args apply-op stack push
            ] }
        } case
    ] each
    "ok\n" stack first >float number>string append "factor.txt" utf8 set-file-contents ;

[ check-expression ] [ >string "unsupported\n" prepend "factor.txt" utf8 set-file-contents ] recover
