#!/usr/bin/env raku
# A real Raku grammar. No EVAL, and no host-language expression execution.
grammar Math {
    token TOP { ^ <expression> $ }
    rule expression { <term>+ % <addop> }
    token addop { '+' | '-' }
    rule term { <unary>+ % <mulop> }
    token mulop { '*' | '/' }
    rule unary { <sign>? <power> }
    token sign { '+' | '-' }
    rule power { <postfix> [ '^' <unary> ]? }
    rule postfix { <atom> <unit>? <suffix>* }
    token unit { 'seconds' | 'cm' | 'km' | 'ms' | 'kg' | 'm' | 's' | 'g' }
    token suffix { '!' | '%' }
    rule atom { <number> | <call> | <constant> | <array> | '(' <expression> ')' }
    rule array { '[' <expression>+ % ',' ']' }
    token number { [ \d+ [ '.' \d* ]? | '.' \d+ ] [ <[eE]> <[+\-]>? \d+ ]? }
    rule call { <name> '(' [ <expression>+ % ',' ]? ')' }
    token name { <[a..z]> <[a..z0..9_]>* }
    token constant { 'pi' | 'tau' | 'ans' | 'e' }
}

class Compile {
    method TOP($/) { make $<expression>.made }
    method expression($/) {
        my @out = |$<term>[0].made;
        for $<addop>.list.kv -> $i, $op {
            @out.append: |$<term>[$i + 1].made;
            @out.push: 'F ' ~ ($op.Str eq '+' ?? 'add' !! 'sub') ~ ' 2';
        }
        make @out;
    }
    method term($/) {
        my @out = |$<unary>[0].made;
        for $<mulop>.list.kv -> $i, $op {
            @out.append: |$<unary>[$i + 1].made;
            @out.push: 'F ' ~ ($op.Str eq '*' ?? 'mul' !! 'div') ~ ' 2';
        }
        make @out;
    }
    method unary($/) {
        my @out = |$<power>.made;
        @out.push('F neg 1') if $<sign> && $<sign>.Str eq '-';
        make @out;
    }
    method power($/) {
        my @out = |$<postfix>.made;
        if $<unary> { @out.append: |$<unary>.made; @out.push: 'F pow 2' }
        make @out;
    }
    method postfix($/) {
        my @out = |$<atom>.made;
        @out.push('F unit_' ~ $<unit>.Str ~ ' 1') if $<unit>;
        for $<suffix>.list -> $suffix {
            @out.push: 'F ' ~ ($suffix.Str eq '!' ?? 'fact' !! 'percent') ~ ' 1';
        }
        make @out;
    }
    method atom($/) {
        if $<number> { make ['N ' ~ $<number>.Str] }
        elsif $<call> { make $<call>.made }
        elsif $<constant> { make ['C ' ~ $<constant>.Str] }
        elsif $<array> { make $<array>.made }
        else { make $<expression>.made }
    }
    method call($/) {
        my @out;
        for $<expression>.list -> $expr { @out.append: |$expr.made }
        @out.push: 'F ' ~ $<name>.Str ~ ' ' ~ $<expression>.elems;
        make @out;
    }
    method array($/) {
        my @out;
        for $<expression>.list -> $expr { @out.append: |$expr.made }
        @out.push: 'F array ' ~ $<expression>.elems;
        make @out;
    }
}

try {
    my $source = 'normalized.txt'.IO.slurp.trim;
    my $parsed = Math.parse($source, actions => Compile.new);
    die 'Check parentheses, commas, and operators. Use * for multiplication (2*pi).' unless $parsed;
    my @instructions = |$parsed.made;
    die 'This expression is too complex (maximum 256 instructions).' if @instructions.elems > 256;
    'tokens.txt'.IO.spurt: @instructions.join("\n") ~ "\n";
    CATCH { default { 'error.txt'.IO.spurt: .message; exit 1 } }
}
