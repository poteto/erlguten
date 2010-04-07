%%======================================================================
%% xml parser
%%----------------------------------------------------------------------
%% Copyright (C) 2003 Joe Armstrong
%%
%%   General Terms
%%
%%   Erlguten  is   free  software.   It   can  be  used,   modified  and
%% redistributed  by anybody for  personal or  commercial use.   The only
%% restriction  is  altering the  copyright  notice  associated with  the
%% material. Individuals or corporations are permitted to use, include or
%% modify the Erlguten engine.   All material developed with the Erlguten
%% language belongs to their respective copyright holder.
%% 
%%   Copyright Notice
%% 
%%   This  program is  free  software.  It  can  be redistributed  and/or
%% modified,  provided that this  copyright notice  is kept  intact. This
%% program is distributed in the hope that it will be useful, but without
%% any warranty; without even  the implied warranty of merchantability or
%% fitness for  a particular  purpose.  In no  event shall  the copyright
%% holder  be liable  for  any direct,  indirect,  incidental or  special
%% damages arising in any way out of the use of this software.
%%
%% Authors:   Joe Armstrong <joe@sics.se>
%% Last Edit: 2003-03-11
%% =====================================================================

-module(erlguten_xml_lite).

-export([parse_all_forms/2, parse_single_form/2, parse_file/1,
	 continue/2, pp/1, xml2bin/2, bin2xml/2, test/1]).
-compile(export_all).

-import(lists, [map/2, member/2, all/2, reverse/1, sort/1]).

%% Test cases


test(2) ->
    {more, C} = parse_single_form("<", 0),
    continue(C, "abc>");
test(3) ->
    reent_test("<a def=\"ads\"   ghi  = 'abc'  >aa<b>aaa</b>gg<ab/>aa<abc a='bb' /></a>");

test(7) ->
    parse_all_forms("<p>aaaa<![CDATA[
zip a doodly]]> aa </p>").

%% This is a reentrant parser for XML streams

%% +deftype parse_result() =  {ok, xmlParseTree(), RestString : string()}
%%                         |  {more, cont()}
%%                         |  {error, parse_error()}
%% +type start(Str)                   -> parse_result().
%% +type more(Str, Cont)              -> parse_result().
%% +type format_error(parser_error()) -> string().
%% +type start_cont()                 -> cont().

%% parse_file(File) -> {error, What} | [Forms]

parse_file(String) ->
	Result = parse_all_forms(String, 1),
	Result.

xml2bin(In, Out) ->
    case file:read_file(In) of
	{ok, Bin} ->
	    case parse_all_forms(binary_to_list(Bin), 0) of
		{ok, Tree, _} ->
		    file:write_file(Out, term_to_binary(Tree));
		E = {error, X} ->
		    E;
		{more, _} ->
		    {error, incomplete}
	    end;
	Error ->
	    Error
    end.

bin2xml(In, Out) ->
    case file:read_file(In) of
	{ok, Bin} ->
	    Tree = binary_to_term(Bin),
	    file:write_file(Out, pp(Tree));
	Error ->
	    Error
    end.

atomize(A={Atom,_}) when atom(Atom) ->
    A;
atomize({Str,Args,List}) -> 
    {list_to_atom(Str), Args, map(fun atomize/1, List)}.
    
%%----------------------------------------------------------------------

%% Top level  ...

parse_all_forms(Str) -> parse_all_forms(Str, 0).

parse_all_forms(Str, Line) -> top_parse_loop(Str, Line, []).

top_parse_loop(Str, Line, L) ->
    case parse_single_form(Str, Line) of
	{ok, Form, Str1, Line1} -> 
	    case all_blanks(Str1) of
		true ->
		    reverse([Form|L]);
		false ->
		    top_parse_loop(Str1, Line1, [Form|L])
	    end;
	E={error, Why} ->
	    E;
	{more, Cont} ->
	    {error, more_data_expected}
    end.

parse_single_form(Str, Line) ->
    parse([], Str, Line).

continue(Cont, Str) ->
    Cont(Str).

parse(State, Str, Line) ->
    tokenise_result(erlguten_xml_tokenise:get_next_token(Str, Line), State).

parse_cont(State, Cont, Str) ->
    tokenise_result(erlguten_xml_tokenise:continue(Cont, Str), State).

tokenise_result({error, Line, What}, State) ->
    {error,{errorInLine,Line,What}};
tokenise_result({done, Token, Str1, Line1}, State) ->
    %% io:format("Token= ~p Str1=~p Line1=~p~n",[Token, Str1, Line1]),
    case step_parser(State, Token) of
	{more, State1} ->
	    parse(State1, Str1, Line1);
	{done, Parse} ->
	    {ok, Parse, Str1, Line1};
	{error, What} ->
	    {error, {errorInLine, Line1,What}}
    end;
tokenise_result({more, Cont}, State) ->
    {more, fun(Str) -> parse_cont(State, Cont, Str) end}. 
			   
%% The Stack is just [{STag,Args,Collected}]
%% pcdata and completed frames are just pushed onto the stack
%% When an end tag is found it is compared with the start tag
%% if it matches the stack frame is popped and it is
%% merged into the previous stack frame

%% step_parser(State, Event) -> {more, State1} | {done, Parse} | {error, What}

step_parser(Stack, {sTag, _, Tag, Args}) ->
    %% Push new frame onto the stack
    {more, [{Tag, sort(Args), []}|Stack]};
step_parser([{Tag,Args,C}|L], P={Flat, _, D}) when Flat == pi;
						   Flat == raw;
						   Flat == cdata;
						   Flat == comment;
						   Flat == doctype ->
    {more, [{Tag,sort(Args),[{Flat,D}|C]}|L]};
step_parser([{Tag,Args,C}|L], {empty, _, TagE, ArgsE}) ->
    {more, [{Tag,Args,[{TagE,sort(ArgsE),[]}|C]}|L]};
step_parser([{Tag, Args, C}|L], {eTag, _, Tag}) ->
    %% This is a matching endtag
    %% Now we normalise the arguments that were found
    C1 = deblank(reverse(C)),
    pfinish([{Tag,Args,C1}|L]);
step_parser([{STag, Args, C}|L], {eTag, _, Tag}) ->
    {error,{badendtagfound,Tag,starttagis,STag}};
step_parser([], {raw, _, S}) ->
    case all_blanks(S) of
	true ->
	    {more, []};
	false ->
	    {error, {nonblank_data_found_before_first_tag, S}}
    end;
step_parser([], {Tag,_,D}) when Tag==comment; Tag==doctype; Tag==pi ->
    {done, {Tag, D}};
step_parser(S, I) ->
    io:format("UUgh:Stack=~p Item=~p~n",[S, I]).


pfinish([X])                 -> {done, {xml, atomize(X)}};
pfinish([H1,{Tag,Args,L}|T]) -> {more, [{Tag,Args,[H1|L]}|T]}.

deblank(S=[{raw, C}]) -> S;
deblank(X) -> deblank1(X).

deblank1([H={raw,X}|T]) ->
    case all_blanks(X) of
	true  -> deblank1(T);
	false -> [H|deblank1(T)]
    end;
deblank1([H|T]) ->
    [H|deblank1(T)];
deblank1([]) ->
    [].

all_blanks(L) -> all(fun is_Blank/1, L).

is_Blank($ )  -> true;
is_Blank($\n) -> true;
is_Blank($\t) -> true;
is_Blank($\r) -> true;
is_Blank(_)   -> false.


%% Pretty printer

pp(Tree) ->
    pp(Tree, 0).

pp({Node,Args,[{raw,Str}]}, Level) ->
    S = name(Node),
    [indent(Level),"<",S,pp_args(Args),">",Str,"</",S,">\n"];
pp({Node,Args,[]}, Level) ->
    S = name(Node),
    [indent(Level),"<",S,pp_args(Args),"></",S,">\n"];
pp({Node,Args,L}, Level) ->
    S = name(Node),
    [indent(Level),"<",S,pp_args(Args),">\n",
     map(fun(I) -> pp(I, Level+2) end, L),
     indent(Level),"</",S,">\n"];
pp({raw,Str}, Level) ->
    [indent(Level),Str,"/n"];
pp(X, Level) ->
    io:format("How do I pp:~p~n",[X]),
    ["oops"].
    
pp_args([]) -> [];
pp_args([{Key,Val}|T]) ->
    Q=quote(Val),
    [" ",name(Key),"=",Q,Val,Q|pp_args(T)].

quote(Str) ->
    case member($", Str) of
	true  -> $';
	false -> $"
    end.

name(X) ->
    atom_to_list(X).

indent(0) -> [];
indent(N) -> [$ |indent(N-1)].

reent_test(O)->a.

    


%%------------------------------------------------------------------------------
%% Tests
%%------------------------------------------------------------------------------







