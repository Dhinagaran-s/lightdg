from lightdg import HTTPRequest, HTTPResponse, Server
from lightdg.api.routing import BaseRequest, FromReq, RootRouter, Router, HandlerResponse, JSONType, RouterBase


# A simpler approach that directly handles your specific case
from lightdg import HTTPRequest, HTTPResponse, Server, HTTPService, OK, NotFound
from lightdg.http import RequestMethod


struct App(Copyable, Movable):
    var router: RootRouter

    fn __init__(out self) raises:
        self.router = RouterBase[True]("/")

    fn get[T: FromReq = BaseRequest](mut self, path: String, handler: fn (T) raises -> HandlerResponse) raises:
        self.router.get[T](path, handler)

    fn post[T: FromReq = BaseRequest](mut self, path: String, handler: fn (T) raises -> HandlerResponse) raises:
        self.router.post[T](path, handler)

    fn add_router(mut self, owned router: Router) raises -> None:
        self.router.add_router(router)

    fn start_server(mut self, address: String = "0.0.0.0:8091") raises:
        var server = Server()
        server.listen_and_serve(address, self.router)


struct SimpleApp(Copyable, HTTPService, Movable):
    fn __init__(out self):
        pass

    fn func(mut self, req: HTTPRequest) raises -> HTTPResponse:
        var path = req.uri.path
        var method = req.method

        # Direct routing logic
        if method == RequestMethod.get.value and path == "/":
            return OK("Hello 🔥!")
        else:
            return NotFound(path)

    fn start_server(mut self, address: String = "0.0.0.0:8086") raises:
        var server = Server()
        server.listen_and_serve(address, self)
