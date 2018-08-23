---
title: "Building an HTTP server - Go and RFCs"
date: 2018-08-23T13:07:05-04:00
---

For whatever reason, I decided it would be fun to write my own HTTP server last weekend.
I've been wanting to start another Go project for a bit, since it's been awhile, and a low-level project like this seemed perfect for it.
Also, I've never built something using only the RFC as a reference doc - so that looked like a cool challenge.

[Here's a link](https://github.com/belljustin/jserver) to the "finished" product. 

# Goal

Build a simple HTTP server in Go using the RFCs as reference.
It must:

- Answer and reply to simple HTTP requests made by existing tools, like `curl`
- Read the provided request headers
- Provide an interface for the server to be extended with general use handlers

# Request for Comments (RFC)

Request for Comments are publications that convey new concepts, information, and [sometimes humour](https://www.rfc-editor.org/rfc/rfc748.txt).
Some of these proposals are adopted as Internet Standards by the Internet Engineering Task Force.
Many seminal contributions that made the internet we know today are specified in These documents including: [IP](https://tools.ietf.org/html/rfc791), [TCP](https://tools.ietf.org/html/rfc793), and - yes - [HTTP](https://tools.ietf.org/html/rfc2616).

But they're not just relics of the (relatively speaking) distant past.
RFCs continue to be the primary method of standardizing new and important inventions like: [SSL](https://tools.ietf.org/html/rfc6101), [WebSockets](https://tools.ietf.org/html/rfc6455), and [oAuth](https://tools.ietf.org/html/rfc6749)

It can be intimidating trying to write code based on an RFC.
The documents can be long (the original HTTP RFC is 176 pages), densely interconnected, and crammed with strictly used wording.
Not to mention how daunting it can be to face down the famous authors and institions that litter the front pages of these docs - Roy Fielding, Tim Berners-Lee, DARPA.
But once you get past all this it's actually pretty fun.
If all the software I wrote was this well specified, life would be pretty easy!

# Listening for Connections

But, before we can get into parsing HTTP messages, we need to grab our connections.
Here's the code block we'll be breaking down that does that:

{{< highlight go "linenos=inline">}}
const (
    HOST = "localhost"
    PORT = 8080
)

func main() {
    listen := fmt.Sprintf("%s:%d", HOST, PORT)

    ln, err := net.Listen("tcp", listen)
    if err != nil {
        fmt.Println(err)
    }

    fmt.Printf("Accepting connections on %s\n", listen)
    for {
        conn, err := ln.Accept()
        if err != nil {
            fmt.Println(err)
        }
        go handleConnection(conn, echoHandler)
    }
}
{{< /highlight >}}

This is practically pulled from the golang `net` documentation.
At the top, we define a few constants - `HOST`, `PORT`.
For now, I've defined host as "localhost" meaning the server will only be accessible from my local machine.
For security reasons, the server needs to be run with superuser privileges to listen for arbitrary connections.
For similar reasons, I'm using a high port number instead of the typical well-known HTTP port, 80.

{{< highlight go "linenos=inline">}}
    ln, err := net.Listen("tcp", listen)
    if err != nil {
        fmt.Println(err)
    }
{{< /highlight >}}

As shown above, Listening for connections in Go is pretty straightforward.
Just specify the protocol to use, and host:port combo as a string.
Theoretically, you could use any transport protocol to implement HTTP (like UDP, for instance) but it's almost _always_ implemented over TCP because, among many other reasons, it is [reliable](https://en.wikipedia.org/wiki/Reliability_(computer_networking)).

This is as good a time as any to point out that this is not robust software (surprise).
In the event of an error, I'm just printing it out for debugging purposes and letting the program go chugging along it's merry path of destruction and senselessness.
But this is just a toy, so let's move on...

{{< highlight go "linenos=inline">}}
    fmt.Printf("Accepting connections on %s\n", listen)
    for {
        conn, err := ln.Accept()
        if err != nil {
            fmt.Println(err)
        }
        go handleConnection(conn, echoHandler)
    }
{{< /highlight >}}

After annoucing that we're ready for business, we open up an infinite loop which is done in idiomatic go with a for loop without conditions.
From there we call the `ln.Accept()` method on our listener which blocks until it can return a new connection (once again with excellent exception handling /s).
With this new connection at the ready, we hand it off to our handleConnection method in a goroutine which will run conncurrently so we can get back to the beginning of our loop and be ready to grab the next incoming connection.

# Handling Connections

But what is this `handleConnection` method?
Simply put: it reads the request from the connection, dispatches the request to the provided handler, and writes the handlers response back to the connection.

{{< highlight go "linenos=inline">}}
func handleConnection(conn net.Conn, handle handler) {
    defer conn.Close() // make sure the connection gets closed at the end

    fmt.Println("Handling connection")

	headerBuf, bodyBuf := request.ReadHeader(conn)
    req := request.ParseRequest(headerBuf, bodyBuf)
    fmt.Printf("%+v\n", req)

    res := handle(req)
    conn.Write(res.Bytes())
}
{{< /highlight >}}

Naturally, this means `handler`s are defined as such:

{{< highlight go "linenos=inline">}}
type handler func(*Request) *Response
{{< /highlight >}}

Defining the handler function type and passing it as an argument to `handleConnection` allows the server to be used more generally.
As long as your application can be defined as a function that processes a `Request` and returns a `Response`, the server can handle it.
For instance, here we implemented an `echoHandler` which repeats back to the client whatever you sent - but more on that later.

# Requests

[RFC 7230](https://tools.ietf.org/html/rfc7230#section-3), Hypertext Transfer Protocol (HTTP/1.1): Message Syntax and Routing, defines an HTTP-mesage as such:

```txt
     HTTP-message   = start-line
                      *( header-field CRLF )
                      CRLF
                      [ message-body ]
```

If you're anything like me, this syntax isn't all that familiar at first glance.
However, near the beginning of the RFC, under the heading "1.2.  Syntax Notation" they link us to [RFC 5234](https://tools.ietf.org/html/rfc5234) which defines the Augmented Backus-Naur Form (ABNF) notation which defines a grammar for compactly and conveniently describing the message structures.

## ABNF

We won't go over that entire 16 page document - I certainly didn't - but we'll reference it when we encounter relevant notation.
It may seem a little tedious at first, but it makes the entire process really painless and straightforward when followed carefully.

### Rule Form

First we have the rule form:

```txt
name = elements crlf
```

`name` is the identifier of the rule and must begin with an alphabetic character followed by alphabetics, digits, or hyphens.
It is case-insensitve.

All rules are terminated by the value definition CRLF.
Value definitions are terminal values which are just combinations of non-negative integers.
In this case CRLF are the decimal numbers 13 10 - in ASCII these represent '\r' '\n', hence it also being called carriage-return line-feed.

Finally, we have elements which are just other rules or terminal values.

### Bracket, Asterisk, and Parentheses

Three more simple notations and we can decode the HTTP-message rule.

\* means any number, including zero of the following elements

\(\) groups elements together; we can use operators like \* on a group of elements without defining a whole new rule.

And \[\] implies an optional group.

## Back to the Request

Now the HTTP-message should be pretty easy to decode.

```
     HTTP-message   = start-line
```

An HTTP=message rule starts with the (creatively named) start-line rule.

```
                      *( header-field CRLF )
                      CRLF
```

Followed by any number of CRLF terminated header-fields.
We know we've reached the end of the headers when we reach a CRLF on a line all by itself.

## Reading the Header

The start-line and the header-fields together are called the header and we'll first focus on reading those from the connection before going any further.
I'll start by showing this process in it's entirety and then going through it bit by bit:

{{< highlight go "linenos=inline">}}
func ReadHeader(r io.Reader) (headerBuf bytes.Buffer, bodyBuf bytes.Buffer) {
    tmp := make([]byte, 256)

    // delim CRLF CRLF marks the end the header
    delim := [...]byte{'\r', '\n', '\r', '\n'}
    i := 0

    for {
        n, _ := r.Read(tmp)

        for m, b := range tmp {
            if b == delim[i] {
                i += 1 // increment the counter if the next delim is found
            } else {
                i = 0 // if we miss a delim, reset the counter
            }

            // if entire delim is found, write part before to headerBuf and
            // the rest to the body buffer
            if i == len(delim) {
                headerBuf.Write(tmp[:m])
                bodyBuf.Write(tmp[m:n])
                return headerBuf, bodyBuf
            }
        }

        headerBuf.Write(tmp[:n])
    }
    return headerBuf, bodyBuf
}
{{< /highlight >}}

First, the signature:

{{< highlight go "linenos=inline">}}
func ReadHeader(r io.Reader) (headerBuf bytes.Buffer, bodyBuf bytes.Buffer) {
{{< /highlight >}}

As the input, we take an object that implements the `io.Reader` interface which means it must at least have a `Read(p []byte) (n int, err error)` method which will allow us to pull data off the connection.
It outputs both a `headerBuf` and a `bodyBuf`. 
For now, we're really only interested in the `headerBuf`.
The reason we're also outputting a bodyBuf is because, as we'll see shortly, we're reading from the connection in chunks and we might read some of body data which we don't want to lose track of.

{{< highlight go "linenos=inline">}}
    tmp := make([]byte, 256)

    // delim CRLF CRLF marks end of the header
    delim := [...]byte{'\r', '\n', '\r', '\n'}
    i := 0
{{< /highlight >}}

The next little bit of setup includes a temporary byte array, `tmp`, which we'll use to read from the connection into before parsing. 
No special rhyme or reason to 256 - just a reasonably sized power of 2.
After that we have the `delim` which is the bytestring which marks the end of the header, and the integer `i` which we'll use for counting our position in the delim.

{{< highlight go "linenos=inline">}}
    for {
        n, _ := r.Read(tmp)

        ...

        headerBuf.Write(tmp[:n])
    }
    return headerBuf, bodyBuf
}
{{< /highlight >}}

Ignoring the delimiter logic in the middle for a moment, makes the rest really clear.
We keep reading the bytes from the connection, `r`, into `tmp` and writing the `n` bytes that were read into the headerBuf.

{{< highlight go "linenos=inline">}}
        for m, b := range tmp {
            if b == delim[i] {
                i += 1 // increment the counter if the next delim is found
            } else {
                i = 0 // if we miss a delim, reset the counter
            }

            // if entire delim is found, write part before to headerBuf and
            // the rest to the body buffer
            if i == len(delim) {
                headerBuf.Write(tmp[:m])
                bodyBuf.Write(tmp[m:n])
                return headerBuf, bodyBuf
            }
        }
{{< /highlight >}}

Here we loop over the `tmp` byte array looking for the delim chars and incrementing our counter as we find them - noting that we reset the counter in the event that one of the characters do not match. 

Then, if we've found the entire sequence of delimiters, we write the sequence of characters before and including the delimiters into the header buffer and the remaining are written to the body buffer so as not to lose bytes we've already read.

## Parsing the Header

Now that we have the entire header in a buffer, we can deserialize it into a convenient data structure.

### Request Line

On requests (as opposed to responses) the start-line is known as the request-line.
It is defined by the rule below

```
request-line   = method SP request-target SP HTTP-version CRLF
```

Method can be any token though it is almost always reserved for the familiar HTTP verbs like GET, POST, etc.
In fact, [RFC7231](https://tools.ietf.org/html/rfc7231#section-4), which describes all the commonly known methods, only specifies servers *MUST* support GET and HEAD.

The request-target has a complex series of rules that are beyond the scope of my little project.
For our purposes, I just matched any token, and considered this field to be the location of our resource like root `/`, a file location `/index.html`, or a REST resource `/users/justin/debits`.

And finally the HTTP-version matches this rule:

```
HTTP-name = %x48.54.54.50
HTTP-version = HTTP-name "/" DIGIT "." DIGIT
```

Where `%x48.54.54.50` is the hexidecimal ASCII representation of "HTTP".
So altogether, for the version we're basing our spec off, it's "HTTP/1.1".

And here's a simple little data struct to wrap it all up:

{{< highlight go "linenos=inline">}}
type RequestLine struct {
	Method     string
	RequestURI string
	Version    string
}

{{< /highlight >}}

### Header Fields

The last part of the header is the header fields:

```
     header-field   = field-name ":" OWS field-value OWS
     field-name     = token
     field-value    = *( field-content )
     field-content  = field-vchar [ 1*( SP / HTAB ) field-vchar ]
```

Here we have a few new terminal characters.
`HTAB` is, perhaps obviously, horizontal tab.
OWS, optional whitespace, follows naturally as: `OWS = *( SP / HTAB )` - any number of spaces or horizontal tabs.

We also have an extension of the asterisk notation: `<m>*`. This means that we have at least `m` matching elements but possibly infinitely more; in this case `m=1`.

Altogether, this means that we have a key-value pair where keys are the field-name followed by a colon and any natural number of values seperated by spaces or tabs.
Many standard headers have more specific rules but, for this application, we'll only considered the ones provided above.
A typical example is the `Accept` header which informs the server which content types the client is willing to handle:

```http
Accept: text/plain, text/html
```

### Request struct

Leveraging the `RequestLine` struct defined before, we end up with something like this:

{{< highlight go "linenos=inline">}}
type Request struct {
	RequestLine
	Headers map[string]string
	Body    string
}
{{< /highlight >}}

### Parsing

From here, we can define a method for building a request from the headerBuf.
Below we build a scanner that splits on new lines, which conveniently delimits the request line and each header, then hand it off to relevant functions to be parsed.
After all the parsing, we return a pointer to a request object whose entire header has been filled in.

{{< highlight go "linenos=inline">}}
func ParseRequestHeader(buf bytes.Buffer) *Request {
	scanner := bufio.NewScanner(&buf)
	scanner.Split(bufio.ScanLines)

	// request-line
	scanner.Scan()
	requestLine := parseRequestLine(scanner.Bytes())

	// headers
	headers := make(map[string]string)
	scanner.Scan()
	l := scanner.Bytes()
	for len(l) > 0 {
		fieldName, fieldContent := parseHeaderField(l)
		headers[fieldName] = fieldContent
		scanner.Scan()
		l = scanner.Bytes()
	}

	return &Request{
		*requestLine,
		headers,
		"",
	}
}
{{< /highlight >}}

### Parse Headers

In the interest of brevity, I'll only go through one of the parsers, `parseHeaderField`, but the request-line parser follows the same idea.

{{< highlight go "linenos=inline">}}
func parseHeaderField(b []byte) (string, string) {
	r := regexp.MustCompile("^([^:]*):(?: )*?([^ ].*)$")
	matches := r.FindStringSubmatch(b)
	fieldName := matches[1] 
	fieldContent := matches[2] 
	return fieldName, fieldContent
}
{{< /highlight >}}

This method returns the field-name and the field-value for each header field line.

I have to admit I'm no regex expert and the pattern on line two came with a fair bit of trial and error.
I found testing with this [online tool](https://regex101.com/) really helpful - especially with the side bar which explains how the pattern is matched as you hover over each one.

Nonetheless, I'll do my best at breaking it down, though the rest of this section is definitely skip worthy if you're not already familiar with regex.

The first caret symbol, `^`, denotes the beginning of the line and the dollar sign, `$`, at the end denotes the end of the line.
We match our first group with parenthesis, `(...)`, and inside we tell it to match anything, `*`, except colon, `[^:]*`.

This is directly followed by a colon and optionally any number of whitespaces, `:(?: )*?`.
The `?:` inside the parenthesis just means that we don't want to include that group in our matches.

After that, we capture a new group, where we ignore the first space, `[^ ]` and capture all remaining characters `.*`.

It's worth noting that my matches don't start at the 0 index because it will first match the entire string - instead we get the subgroups 1 and 2, which are the field-name and field-value respectively.

### Parsing the Body

For a simple GET request, we can safely ignore the body of the message, however it would be nice to read the body for a POST request.
Also, POST requests *SHOULD* have a `Content-Length` header that tells us how many bytes are in the body - so we can use that to know how much more of the body to read.

{{< highlight go "linenos=inline">}}
// If request is POST, use Content-Length header to read rest of request
if req.Method == "POST" {
	n, found := req.Headers["Content-Length"]
	if !found {
		panic("No Content-Length for POST request")
	}

	m, _ := strconv.Atoi(n) // TODO: handle error
	tmp := make([]byte, (m+1)-bodyBuf.Len())
	conn.Read(tmp) // TODO: handle error
	bodyBuf.Write(tmp)
	req.Body = bodyBuf.String()
}
{{< /highlight >}}

Above we made the check on the method type, and read the `Content-Length` header.
Remember that it's possible/likely we already read some of the bytes when parsing the header, so we have to subtract the length of that from `Content-Length` bewfore trying to read the remaining bits.
Then finally, we can add the body to the request and completely finishing reading the request!

## Building a Response

Now all that's left is building a response and writing it back to the channel.
Thankfully, this is much easier since we don't have to do any parsing.

A Response follows the same ABNF rules as a request except the request-line is replaced by a status-line, like so:

```
status-line = HTTP-version SP status-code SP reason-phrase CRLF
```

The HTTP-version is already familiar to us.

The status-code is a 3 digit integer code describing the result of the request.
These include familiar codes like, 200 OK, and 404 Not Found.
A comprehensive list of these codes and their semantics is found in [RFC7231#section6](https://tools.ietf.org/html/rfc7231#section-6).

The reason-phrase is perhaps less familiar since it's not commonly useful.
It gives a textual description of the status-code and the RFC says it exists "mostly out of deference to earlier Internet application protocols that were more frequently used with interactive text clients."

Altogether this gives us the StatusLine struct.
We'll also want a method to serialize it for writing to the connection.

{{< highlight go "linenos=inline">}}
type StatusLine struct {
	Version      string
	StatusCode   int
	ReasonPhrase string
}

func (sl *StatusLine) Bytes() []byte {
	values := [][]byte{
		[]byte(sl.Version),
		[]byte(strconv.Itoa(sl.StatusCode)),
		[]byte(sl.ReasonPhrase),		
	}
	return bytes.Join(values, []byte(" "))
}
{{< /highlight >}}

And adding the headers and the response body we get the Response struct.
Again, we'll need a method for serializing the whole thing.

{{< highlight go "linenos=inline">}}
type Response struct {
	StatusLine
	Headers map[string]string
	Body    string
}

func (res *Response) Bytes() []byte {
	values := [][]byte{
		[]byte(res.StatusLine)
		[]byte(""),
		[]byte(res.Body),
	}
	return bytes.Join(values, []byte["\r\n"])
}
{{< /highlight >}}

## Sending Response

Finally the last step!

For the actual response, we're just going to echo the request body back at the client.
Here's our handler to do that:

{{< highlight go "linenos=inline">}}
func echoHandler(req *request.Request) *response.Response {
	headers := make(map[string]string)
	return NewResponse(200, headers, req.Body) // response constructor that fills in the relevant fields
}
{{< /highlight >}}

### curl

After building and starting our server, we can now hit it with POST request via curl.
Using the `-X` flag allows us to specify the method.
`-d` is used to provide the data or body of the request.

```sh
$ curl http://localhost:9090 -X POST -d "hello world"

hello world
```

Also, we printed the request in the server so we should see something like the following in the same spot we launched our server from.

```
&{ RequestLine: {
        Method:POST
        RequestURI:/
        Version:HTTP/1.1
    } Headers: map[
        User-Agent:curl/7.54.0
        Accept:*/*
        Content-Length:11
        Content-Type:application/x-www-form-urlencoded
        Host:localhost:9090
    ] Body:
        hello world
}
```
