from lightbug_http import *
from os.env import getenv
from time import monotonic

@fieldwise_init
struct ExampleRouter(HTTPService):
    fn func(mut self, req: HTTPRequest) raises -> HTTPResponse:
        var body = req.body_raw
        var uri = req.uri
        var start_time = monotonic()

        if uri.path == "/":
            print("I'm on the index path! in ", monotonic()-start_time)
        if uri.path == "/first":
            print("I'm on /first! in ", monotonic()-start_time)
        elif uri.path == "/second":
            print("I'm on /second! in ", monotonic()-start_time)
        elif uri.path == "/echo":
            print(to_string(body))

        return OK(body)


fn main() raises:
    var server = Server()
    var handler = ExampleRouter()

    var host = getenv("DEFAULT_SERVER_HOST", "localhost")
    var port = getenv("DEFAULT_SERVER_PORT", "8086")

    server.listen_and_serve(host + ":" + port, handler)