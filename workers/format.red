Red [Title: "WonkyCalc / result presentation" Version: 1.0.0]

; Round decimal digits directly. Red's approximate float equality and ROUND/TO
; can collapse very small values to zero; formatting must not lose them.
raw: lowercase trim read %result.txt
context: split trim read %context.txt newline
precision: to integer! third context
problem: try [
    negative?: raw/1 = #"-"
    if negative? [remove raw]
    parts: split raw "e"
    exponent: either 2 = length? parts [to integer! second parts] [0]
    mantissa: first parts
    point: find mantissa "."
    decimal-position: either point [(index? point) - 1] [length? mantissa]
    exponent: exponent + decimal-position - 1
    digits-text: replace/all copy mantissa "." ""
    while [all [not empty? digits-text digits-text/1 = #"0"]] [
        remove digits-text
        exponent: exponent - 1
    ]
    either empty? digits-text [display: "0"] [
        round-up?: all [
            (length? digits-text) > precision
            (pick digits-text (precision + 1)) >= #"5"
        ]
        digits-text: copy/part digits-text precision
        if round-up? [
            position: length? digits-text
            carry?: true
            while [all [position > 0 carry?]] [
                digit: pick digits-text position
                either digit = #"9" [poke digits-text position #"0"] [
                    poke digits-text position (to char! ((to integer! digit) + 1))
                    carry?: false
                ]
                position: position - 1
            ]
            if carry? [
                insert digits-text "1"
                digits-text: copy/part digits-text precision
                exponent: exponent + 1
            ]
        ]
        while [all [(length? digits-text) > 1 (last digits-text) = #"0"]] [
            remove back tail digits-text
        ]
        either any [exponent >= precision exponent < -6] [
            display: copy/part digits-text 1
            if (length? digits-text) > 1 [append display "." append display next digits-text]
            append display "e"
            append display form exponent
        ] [
            either exponent < 0 [
                display: copy "0."
                append/dup display #"0" (negate (exponent + 1))
                append display digits-text
            ] [
                display: copy digits-text
                decimal-position: exponent + 1
                either decimal-position >= length? display [
                    append/dup display #"0" (decimal-position - length? display)
                ] [insert (skip display decimal-position) "."]
            ]
        ]
        if negative? [insert display "-"]
    ]
    write %formatted.txt display
]
if error? problem [
    write %error.txt "Red could not format the numerical result."
    quit/return 1
]
quit
