:- use_module(library(readutil)).
:- initialization(main, main).

% Arity is a relation, including bounded variadic statistics.
arity(Name, 1) :- memberchk(Name, [neg,percent,sin,cos,tan,asin,acos,atan,
    sinh,cosh,tanh,asinh,acosh,atanh,ln,log,log2,exp,sqrt,cbrt,abs,
    floor,ceil,round,fact,recip,deg,rad]).
arity(Name, 2) :- memberchk(Name, [add,sub,mul,div,pow,root,mod,ncr,npr,gcd,lcm,atan2,logn]).
arity(Name, N) :- memberchk(Name, [sum,mean,median,min,max,stdev,variance,hypot]), between(1,64,N).

check_line(Line, Depth, Next) :-
    split_string(Line, " ", " \r\t", Parts),
    ( Parts = ["N", S] ->
        (catch(number_string(_, S), _, fail) -> Next is Depth+1 ; throw("Invalid number."))
    ; Parts = ["C", C] ->
        (memberchk(C,["pi","tau","e","ans"]) -> Next is Depth+1 ; throw("Unknown constant."))
    ; Parts = ["F", S, Count] ->
        atom_string(Name,S), number_string(N,Count),
        (arity(Name,N) -> true ; format(string(M), 'Unknown function or wrong argument count: ~w(~d arguments).', [Name,N]), throw(M)),
        (Depth >= N -> Next is Depth-N+1 ; throw("An operation is missing an argument."))
    ; throw("Malformed instruction.")
    ),
    (Next =< 128 -> true ; throw("Too many nested arguments." )).

check([], 1) :- !.
check([], _) :- throw("The expression does not reduce to one answer.").
check([Line|Rest], Depth) :- check_line(Line, Depth, Next), check(Rest,Next).

run :-
    read_file_to_string('tokens.txt', Text, []),
    split_string(Text,"\n","\r\n", Lines),
    check(Lines,0),
    setup_call_cleanup(open('validated.txt',write,Out), format(Out,'~s',[Text]),close(Out)).
main :- catch(run, Error, (message(Error,Message), setup_call_cleanup(open('error.txt',write,E),format(E,'~s',[Message]),close(E)),halt(1))).
message(E,E) :- string(E), !.
message(E,M) :- message_to_string(E,M).
