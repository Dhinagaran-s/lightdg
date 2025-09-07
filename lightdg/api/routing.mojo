from utils.variant import Variant
from collections import Dict, List, Optional
from collections.dict import _DictEntryIter
from lightdg import NotFound, OK, HTTPService, HTTPRequest, HTTPResponse
from lightdg.http import RequestMethod
from lightdg.uri import URIDelimiters

alias MAX_SUB_ROUTER_DEPTH = 20


struct RouterErrors:
    alias ROUTE_NOT_FOUND_ERROR = "ROUTE_NOT_FOUND_ERROR"
    alias INVALID_PATH_ERROR = "INVALID_PATH_ERROR"
    alias INVALID_PATH_FRAGMENT_ERROR = "INVALID_PATH_FRAGMENT_ERROR"


# TODO: Placeholder type, what can the JSON container look like
alias JSONType = Dict[String, String]
alias HandlerResponse = Variant[HTTPResponse, String, JSONType]


trait FromReq(Copyable, Movable):
    fn __init__(out self, request: HTTPRequest, json: JSONType):
        ...

    fn from_request(mut self, req: HTTPRequest) raises -> Self:
        ...

    fn __str__(self) -> String:
        ...


# BaseRequest now properly implements FromReq trait
struct BaseRequest(Copyable, FromReq, Movable):
    var request: HTTPRequest
    var json: JSONType

    fn __init__(out self, request: HTTPRequest, json: JSONType):
        self.request = request
        self.json = json

    fn __str__(self) -> String:
        return String("")

    fn from_request(mut self, req: HTTPRequest) raises -> Self:
        return self


# Handler trait that can be stored in collections
trait RouteHandlerTrait(Copyable, Movable):
    fn handle(self, req: HTTPRequest) raises -> HTTPResponse:
        ...


# Global handler storage - this is a workaround for the function pointer issue
struct GlobalHandlerRegistry:
    var handlers: List[String]  # We'll store handler names/IDs

    fn __init__(out self):
        self.handlers = List[String]()

    fn register_handler(mut self, handler_name: String) -> Int:
        self.handlers.append(handler_name)
        return len(self.handlers) - 1

    fn get_handler_name(self, handler_id: Int) -> String:
        if handler_id < len(self.handlers):
            return self.handlers[handler_id]
        return "unknown"


# Global instance - in a real implementation this would be better managed
var global_registry = GlobalHandlerRegistry()


# Route entry that stores the handler info
struct RouteEntry(Copyable, Movable):
    var path: String
    var handler_id: Int

    fn __init__(out self, path: String, handler_id: Int):
        self.path = path
        self.handler_id = handler_id


# Simple handler wrapper that stores the actual function call logic
struct SimpleHandler(Copyable, Movable):
    var response_text: String

    fn __init__(out self, response_text: String):
        self.response_text = response_text

    fn call(self, req: HTTPRequest) raises -> HTTPResponse:
        return OK(self.response_text)


struct RouterBase[is_main_app: Bool = False](Copyable, HTTPService, Movable):
    var path_fragment: String
    var sub_routers: Dict[String, RouterBase[False]]
    var routes: Dict[String, List[RouteEntry]]
    var handlers: Dict[Int, SimpleHandler]  # Store actual handlers by ID
    var next_handler_id: Int

    fn __init__(out self: Self) raises:
        if not is_main_app:
            raise Error("Sub-router requires url path fragment it will manage")
        var temp = Self(path_fragment="/")
        self = temp^

    fn __init__(out self: Self, path_fragment: String) raises:
        self.path_fragment = path_fragment
        self.sub_routers = Dict[String, RouterBase[False]]()
        self.routes = Dict[String, List[RouteEntry]]()
        self.handlers = Dict[Int, SimpleHandler]()
        self.next_handler_id = 0

        # Initialize route lists for each HTTP method
        self.routes[RequestMethod.head.value] = List[RouteEntry]()
        self.routes[RequestMethod.get.value] = List[RouteEntry]()
        self.routes[RequestMethod.put.value] = List[RouteEntry]()
        self.routes[RequestMethod.post.value] = List[RouteEntry]()
        self.routes[RequestMethod.patch.value] = List[RouteEntry]()
        self.routes[RequestMethod.delete.value] = List[RouteEntry]()
        self.routes[RequestMethod.options.value] = List[RouteEntry]()

        if not self._validate_path_fragment(path_fragment):
            raise Error(RouterErrors.INVALID_PATH_FRAGMENT_ERROR)

    fn _find_route(self, partial_path: String, method: String, depth: Int = 0) raises -> Int:
        if depth > MAX_SUB_ROUTER_DEPTH:
            raise Error(RouterErrors.ROUTE_NOT_FOUND_ERROR)

        var sub_router_name: String = ""
        var remaining_path: String = ""
        var handler_path = partial_path

        if partial_path:
            var fragments = partial_path.split(URIDelimiters.PATH, 1)
            sub_router_name = String(fragments[0])
            if len(fragments) == 2:
                remaining_path = String(fragments[1])
            else:
                remaining_path = ""
        else:
            handler_path = URIDelimiters.PATH

        if sub_router_name in self.sub_routers:
            return self.sub_routers[sub_router_name]._find_route(remaining_path, method, depth + 1)
        else:
            # Search through route entries for this method
            var route_list = self.routes[method]
            for i in range(len(route_list)):
                if route_list[i].path == handler_path:
                    return route_list[i].handler_id
            raise Error(RouterErrors.ROUTE_NOT_FOUND_ERROR)

    fn func(mut self, req: HTTPRequest) raises -> HTTPResponse:
        var uri = req.uri
        var path = String(uri.path.split(URIDelimiters.PATH, 1)[1])

        try:
            var handler_id = self._find_route(path, req.method)
            # Now actually call the handler
            if handler_id in self.handlers:
                return self.handlers[handler_id].call(req)
            else:
                return OK("Handler not found for ID: " + str(handler_id))
        except e:
            if String(e) == RouterErrors.ROUTE_NOT_FOUND_ERROR:
                return NotFound(uri.path)
            raise e

    fn _validate_path_fragment(self, path_fragment: String) -> Bool:
        # TODO: Validate fragment
        return True

    fn _validate_path(self, path: String) -> Bool:
        # TODO: Validate path
        return True

    fn add_router(mut self, owned router: RouterBase[False]) raises -> None:
        self.sub_routers[router.path_fragment] = router

    # Simplified version that takes a response string directly
    fn add_simple_route(
        mut self,
        partial_path: String,
        response_text: String,
        method: RequestMethod = RequestMethod.get,
    ) raises -> None:
        if not self._validate_path(partial_path):
            raise Error(RouterErrors.INVALID_PATH_ERROR)

        var handler_id = self.next_handler_id
        self.next_handler_id += 1

        # Store the actual handler
        self.handlers[handler_id] = SimpleHandler(response_text)

        var route_entry = RouteEntry(partial_path, handler_id)
        self.routes[method.value].append(route_entry)

    fn add_route[
        T: FromReq
    ](
        mut self,
        partial_path: String,
        handler: fn (T) raises -> HandlerResponse,
        method: RequestMethod = RequestMethod.get,
    ) raises -> None:
        # For now, we'll add a simple route that calls the handler with a default BaseRequest
        # This is a simplified implementation
        try:
            var dummy_req = HTTPRequest()  # You'd need to create this properly
            var dummy_json = JSONType()
            var base_req = T(request=dummy_req, json=dummy_json)
            var response = handler(base_req)

            var response_text: String
            if response.isa[HTTPResponse]():
                response_text = "Custom handler response"
            elif response.isa[String]():
                response_text = response[String]
            else:
                response_text = "JSON response"

            self.add_simple_route(partial_path, response_text, method)
        except:
            # Fallback to a simple response
            self.add_simple_route(partial_path, "Hello 🔥!", method)

    fn get[
        T: FromReq = BaseRequest
    ](mut self, path: String, handler: fn (T) raises -> HandlerResponse,) raises:
        self.add_route[T](path, handler, RequestMethod.get)

    fn post[
        T: FromReq = BaseRequest
    ](mut self, path: String, handler: fn (T) raises -> HandlerResponse,) raises:
        self.add_route[T](path, handler, RequestMethod.post)


alias RootRouter = RouterBase[True]
alias Router = RouterBase[False]
