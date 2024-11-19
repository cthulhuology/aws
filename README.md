aws - aws interface for Erlang
====================================

This module provides a beamer centric interface to AWS's API.  Currently,
it depends upon my beamer, json, and http modules.


Getting Started
---------------

	Bedrock = aws:service(<<"https://bedrock-runtime.us-east-1.amazonaws.com">>,
		<<"bedrock">>,<<"us-east-1">>, aws:credentials()),
	Request = aws:request(Bedrock,<<"POST">>,
		<<"/model/anthropic.claude-3-5-sonnet-20240620-v1:0/invoke">>,
		[{<<"accept">>,<<"application/json">>},
		 {<<"content-type">>,<<"application/json">>}],
		<<"{\"anthropic_version\":\"bedrock-2023-05-31\",\"messages\":[{ \"role\": \"user\",\"content\":\"write me a sonnet\"}], \"max_tokens\": 40000 }\n">>),
	SignedRequest = aws:sign(Request),
	aws:send(Request),
	aws:then(My,handler).

Basically, the pattern is start the server, register a function or module:function using
then/1 or then/2 as your handler, and then send/1 the an AWS api. Optionally,
you can use post/3 or get/2 for APIs that natively support JSON.

Installing
----------

To use this module you should first install beamer: https://github.com/cthulhuology/beamer

Then you can do the following:

	beamer deps
	beamer make

Assuming your environment is setup correctly, you can then use aws: in your projects.


MIT License

Copyright (c) 2024 David J Goehrig

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
