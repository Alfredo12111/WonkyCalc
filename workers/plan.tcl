# Tcl turns a validated postfix program into named J instructions.
# User text is never evaluated as Tcl or copied into executable J code.
proc readFile {name} { set f [open $name r]; set s [read $f]; close $f; return $s }
proc writeFile {name text} { set f [open $name w]; puts -nonewline $f $text; close $f }
proc jNumber {number} {
    if {![regexp {^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$} $number]} { error "Invalid numeric value." }
    return [string map {- _ + {} E e} $number]
}
proc buildPlan {} {
    set context [split [string trim [readFile context.txt]] \n]
    set angle [lindex $context 0]
    set answer [jNumber [lindex $context 1]]
    set header "wc_degrees =: [expr {$angle eq {DEG} ? 1 : 0}]\n"
    set stack {}; set index 0; set graph {}
    set allowed {add sub mul div pow neg percent sin cos tan asin acos atan sinh cosh tanh asinh acosh atanh ln log log2 exp sqrt cbrt abs floor ceil round fact recip deg rad root mod ncr npr gcd lcm atan2 logn sum mean median min max stdev variance hypot array det transpose norm dot matmul unit_m unit_cm unit_km unit_s unit_ms unit_seconds unit_kg unit_g}
    foreach line [split [string trim [readFile validated.txt]] \n] {
        set fields [split [string trim $line] { }]
        set kind [lindex $fields 0]
        set name [lindex $fields 1]
        set variable "v$index"
        switch -- $kind {
            N { set value [jNumber $name]; append graph "$index\tN\t$name\t-\n" }
            C {
                switch -- $name {
                    pi {set value {(o. 1)}}
                    tau {set value {(2 * o. 1)}}
                    e {set value {(^ 1)}}
                    ans {set value $answer}
                    default {error "Unknown constant."}
                }
                append graph "$index\tC\t$name\t-\n"
            }
            F {
                if {$name ni $allowed} {error "Unknown operation."}
                set count [lindex $fields 2]
                if {![string is integer -strict $count] || $count < 1 || $count > [llength $stack]} {error "Invalid stack."}
                set from [expr {[llength $stack] - $count}]
                set args [lrange $stack $from end]
                set ids {}; foreach arg $args {lappend ids [string range $arg 1 end]}
                append graph "$index\tF\t$name\t[join $ids ,]\n"
                set stack [lrange $stack 0 [expr {$from - 1}]]
                set reads {}
                foreach id $ids { lappend reads "(0\". 1!:1 <'value$id.txt')" }
                set value "(wc_$name ([join $reads { , }]))"
            }
            default {error "Invalid instruction."}
        }
        writeFile "plan-$index.ijs" "${header}wc_answer =: wc_finite $value\n"
        lappend stack $variable
        incr index
    }
    if {[llength $stack] != 1} {error "Invalid final stack."}
    writeFile audit.ijs "${header}wc_answer =: wc_finite (0\". 1!:1 <'audit-value.txt')\n"
    writeFile nodes.tsv $graph
}
if {[catch {buildPlan} problem]} { writeFile error.txt $problem; error $problem }
