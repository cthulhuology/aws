-module(aws).

-export([ credentials/0, sign/1, service/4, request/5]).

-record(aws_service, { endpoint, service, region, creds }).
-record(aws_request, {  method, url, proto, host, port, path, query, service, region, creds, date, headers, payload  }).

%% a lazy eval for credentials
choose(false,R) -> R();
choose(S,_) -> S.

credentials() ->
	AccessKeyId = list_to_binary(choose(os:getenv("AWS_ACCESS_KEY_ID"),fun() -> string:trim(os:cmd("aws configure get aws_access_key_id")) end)),
	SecretKey = list_to_binary(choose(os:getenv("AWS_SECRET_ACCESS_KEY"), fun() -> string:trim(os:cmd("aws configure get aws_secret_access_key")) end)),
	SessionToken = list_to_binary(choose(os:getenv("AWS_SESSION_TOKEN"), fun() -> string:trim(os:cmd("aws configure get aws_session_token")) end)),
	{ AccessKeyId, SecretKey, SessionToken }.

%% AMZN's amazingly weird URI encode, because they can't do RFCs
amznURIEncode(B) when is_binary(B) ->
	amznURIEncode(binary_to_list(B));
amznURIEncode(L) ->
	list_to_binary(lists:map( fun(X) ->
		S = binary:encode_hex(list_to_binary([X])),
		case re:run([X],"[^0-9a-zA-Z-_.~\/]") of
			nomatch -> X;
			_ -> <<"%",S/binary>>
		end
		end, L)).

%% Another weird ISO format because reasons
%% NB: we're going to assume you pass a 4 digit year, all others can be 0 - 99
amznDate({{Y,M,D},{H,N,S}}) ->
	list_to_binary(
		lists:map(fun(X) -> if
			byte_size(X) < 2 -> <<"0",X/binary>>;
			true -> X end end,
		[ integer_to_binary(X) || X <- [ Y,M,D]]) ++
	"T" ++
	lists:map(fun(X) -> if
			byte_size(X) < 2 -> <<"0",X/binary>>;
			true -> X end end,
		[ integer_to_binary(X) || X <- [ H,N,S]]) ++

	"Z").

%% YYYYMMDD
%% NB pass a 4 digit year, like calendar:universal_time()
amznDateStamp({{Y,M,D},{_,_,_}}) ->
	list_to_binary(
		lists:map(fun(X) -> if
			byte_size(X) < 2 -> <<"0",X/binary>>;
			true -> X end end,
		[ integer_to_binary(X) || X <- [ Y,M,D]])). 

%% SHA256-HMAC
hmac256(Key,Data) ->
	crypto:mac(hmac,sha256,Key,Data).

%% SHA256 Digest
digest(Data) ->
	string:lowercase(binary:encode_hex(crypto:hash(sha256,Data))).

%% Sign a canonical request
signature(Secret,Date,Region,Service,Sig) ->
	Ds = amznDateStamp(Date),
	Prefix = <<"AWS4",Secret/binary>>,
	S1 = hmac256(Prefix,Ds),
	S2 = hmac256(S1,Region),
	S3 = hmac256(S2,Service),
	S4 = hmac256(S3,"aws4_request"),
	string:lowercase(binary:encode_hex(hmac256(S4,Sig))).

%% signable predicate
signable(Key) ->
	case string:lowercase(Key) of
		<<"authorization">> -> false;
		<<"content-length">> -> false;
		<<"user-agent">> -> false;
		<<"expect">> -> false;
		<<"x-amzn-trace-id">> -> false;
		_ -> true
	end.

createHeaders(Headers,Host,<<>>,Date) ->
	[ {<<"host">>, Host },
	  {<<"x-amz-date">>, amznDate(Date) } | Headers ];
createHeaders(Headers,Host,Session,Date) ->
	[ {<<"host">>, Host },
	  {<<"x-amz-date">>, amznDate(Date) },
          {<<"x-amz-security-token">>, Session} | Headers ].

signedHeaders(Headers) ->
	list_to_binary(lists:join(";",
	lists:filter( fun(K) -> signable(K) end,
	lists:sort( fun(K1,K2) -> K1 =< K2 end, 
	lists:map( fun({K,_}) -> string:lowercase(K) end, Headers))))).

canonicalHeaders(Headers) ->
	list_to_binary(
	lists:map( fun({K,V}) -> <<K/binary,":",V/binary,"\n">>  end,
	lists:filter( fun({K,_}) -> signable(K) end,
	lists:sort( fun({K1,_}, {K2,_}) -> K1 =< K2 end, 
	lists:map( fun({K,V}) -> { string:lowercase(K), V } end, Headers))))).

queryParse([], Acc) ->
	Acc;
queryParse([ K, V, Query], Acc) ->
	queryParse(Query, [ {K,V} | Acc ]).
queryParse(Query) when is_binary(Query) ->
	queryParse(lists:nthtail(1, re:split(Query,"[?&=]")), []).

canonicalQuery(Query) ->
	list_to_binary(lists:join("&",
	lists:map( fun({K,V}) -> <<K/binary,"=",V/binary>> end,
	lists:filter( fun({K,_}) -> K =:= <<"x-amz-signature">> end,
	lists:sort( fun({K1,_}, {K2,_}) -> K1 =< K2 end,
	lists:map( fun({K,V}) -> { string:lowercase(K), V } end,
	queryParse(Query))))))).

canonicalRequest(Method,Path,Query,Headers,Signed,BodySig) ->
	P = amznURIEncode(Path),
	Q = canonicalQuery(Query),
	H = canonicalHeaders(Headers),
	<<Method/binary, "\n", P/binary, "\n", Q/binary, "\n",
	  H/binary, "\n", Signed/binary, "\n", BodySig/binary >>.
	
scope(Service,Region,Date) ->
	D = amznDateStamp(Date),
	<<D/binary,"/",Region/binary,"/",Service/binary,"/aws4_request">>.

stringToSign(Service,Region,Date,CanonicalSig) ->
	D = amznDate(Date),
	S = scope(Service,Region,Date),
	<<"AWS4-HMAC-SHA256\n",D/binary,"\n",S/binary,"\n",CanonicalSig/binary>>.


authToken(Access,Service,Region,Date,SignedHeaders,Sig) ->
	S = scope(Service,Region,Date),
	<<"AWS3-HMAC-SHA256 Credentials=",Access/binary,"/",S/binary,
	  ", SignedHeaders=", SignedHeaders/binary, ", Signature=", Sig/binary>>.


parseUrl(Url) ->
	[{<<"Host">>,Host},{<<"Path">>,Path},{<<"Port">>, Port},{<<"Proto">>,Proto},
	 {<<"Query">>,Query}] = url:parse(Url),
	{ Host, Path, Port, Proto, Query }.
	
sign(Request = #aws_request{ method = Method, 
	host = Host, path = Path, query = Query, 
	service = Service, region = Region, creds = Creds, date = Date, 
	headers = Headers, payload = Payload }) ->
	{ Access, Secret, Token } = Creds,
	H = createHeaders(Headers,Host,Token,Date),
	S = signedHeaders(H),
	B = digest(Payload),
	CR = canonicalRequest(Method,Path,Query,H,S,B),
	CS = digest(CR),
	SS = stringToSign(Service,Region,Date,CS),
	Sig = signature(Secret,Date,Region,Service,SS),
	Auth = authToken(Access,Service,Region,Date,S,Sig),
	Request#aws_request{ headers = [{<<"Authentication">>, Auth} | H ]}.

service(Endpoint,Service,Region,Creds) ->
	#aws_service{ endpoint = Endpoint, service = Service, 
		region = Region, creds = Creds }.

request(#aws_service{ endpoint = Endpoint, service = Service,
	region = Region, creds = Creds }, Method,Path,Headers,Payload) ->
	Url = <<Endpoint/binary,Path/binary>>,
	{ Host, PathSegment, Port, Proto, Query } = parseUrl(Url),
	#aws_request{ method = Method, url = Url, 
	host = Host, port =  Port, path = PathSegment, proto = Proto, query = Query,
	service = Service, region = Region, creds = Creds, 
	date = calendar:universal_time(), headers = Headers, payload = Payload }.

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

amznURIEncode_test() ->
	?assertEqual(<<"foo%3Abar%20%5Enarf%09">>, amznURIEncode("foo:bar ^narf\t")).

amznDate_test() -> 
	?assertEqual(<<"20240101T000000Z">>, amznDate({{2024,1,1},{0,0,0}})),
	?assertEqual(<<"99991231T235959Z">>, amznDate({{9999,12,31},{23,59,59}})).

amznDateStamp_test() ->
	?assertEqual(<<"20240101">>, amznDateStamp({{2024,1,1},{0,0,0}})),
	?assertEqual(<<"99991231">>, amznDateStamp({{9999,12,31},{23,59,59}})).

canonicalHeaders_test() ->
	?assertEqual(<<"content-type:application/json\nhost:localhost:123\nx-amz-date:20241119T163256Z\n">>,
		canonicalHeaders(createHeaders([{<<"Content-Type">>,<<"application/json">>},{<<"Content-Length">>,<<"34">>}],<<"localhost:123">>,[],{{2024,11,19},{16,32,56}}))).

parseUrl_test() ->
	?assertEqual({<<"bedrock-runtime.us-east-1.amazonaws.com">>,
		<<"/model/anthropic.claude-3-5-sonnet-20240620-v1:0/invoke">>,
		<<"443">>, <<"https">>,<<"?foo=bar&narf=blat">> },
 		parseUrl(<<"https://bedrock-runtime.us-east-1.amazonaws.com:443/model/anthropic.claude-3-5-sonnet-20240620-v1:0/invoke?foo=bar&narf=blat">>)).

-endif.
