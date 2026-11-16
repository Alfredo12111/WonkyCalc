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
    set plan "wc_degrees =: [expr {$angle eq {DEG} ? 1 : 0}]\n"
    set stack {}; set index 0
    set allowed {add sub mul div pow neg percent sin cos tan asin acos atan sinh cosh tanh asinh acosh atanh ln log log2 exp sqrt cbrt abs floor ceil round fact recip deg rad root mod ncr npr gcd lcm atan2 logn sum mean median min max stdev variance hypot}
    foreach line [split [string trim [readFile validated.txt]] \n] {
        set fields [split [string trim $line] { }]
        set kind [lindex $fields 0]
        set name [lindex $fields 1]
        set variable "v$index"
        switch -- $kind {
            N { set value [jNumber $name] }
            C {
                switch -- $name {
                    pi {set value {(o. 1)}}
                    tau {set value {(2 * o. 1)}}
                    e {set value {(^ 1)}}
                    ans {set value $answer}
                    default {error "Unknown constant."}
                }
            }
            F {
                if {$name ni $allowed} {error "Unknown operation."}
                set count [lindex $fields 2]
                if {![string is integer -strict $count] || $count < 1 || $count > [llength $stack]} {error "Invalid stack."}
                set from [expr {[llength $stack] - $count}]
                set args [lrange $stack $from end]
                set stack [lrange $stack 0 [expr {$from - 1}]]
                set value "(wc_$name ([join $args { , }]))"
            }
            default {error "Invalid instruction."}
        }
        append plan "$variable =: wc_finite $value\n"
        lappend stack $variable
        incr index
    }
    if {[llength $stack] != 1} {error "Invalid final stack."}
    append plan "wc_answer =: [lindex $stack 0]\n"
    writeFile plan.ijs $plan
}
if {[catch {buildPlan} problem]} { writeFile error.txt $problem; error $problem }
