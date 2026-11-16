REBOL [Title: "WonkyCalc / input normalization" Version: 1.0.0]

; Input is data, never DO/LOAD/evaluated Rebol code.
text: read/string %request.txt
if 1024 < length? text [write %error.txt "Keep expressions under 1,024 characters." quit/return 1]
foreach [original replacement] [
    "×" "*" "÷" "/" "−" "-" "π" "pi" "τ" "tau"
    "²" "^^2" "³" "^^3" "√" "sqrt" "**" "^^"
] [replace/all text original replacement]
text: lowercase trim text
if empty? text [write %error.txt "Enter an expression first." quit/return 1]
write %normalized.txt text
quit
