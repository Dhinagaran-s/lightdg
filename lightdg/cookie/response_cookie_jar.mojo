from collections import Optional, List, Dict, KeyElement
from lightdg.strings import to_string
from lightdg.header import HeaderKey, write_header
from lightdg.io.bytes import ByteWriter
from hashlib.hasher import Hasher


struct ResponseCookieKey(Copyable, EqualityComparable, Hashable, KeyElement, Movable, Stringable, Writable):
    var name: String
    var domain: String
    var path: String

    fn __init__(
        out self,
        name: String,
        domain: Optional[String] = Optional[String](None),
        path: Optional[String] = Optional[String](None),
    ):
        self.name = name
        self.domain = domain.or_else("")
        self.path = path.or_else("/")

    fn __ne__(self: Self, other: Self) -> Bool:
        return not (self == other)

    fn __eq__(self: Self, other: Self) -> Bool:
        return self.name == other.name and self.domain == other.domain and self.path == other.path

    fn __moveinit__(out self: Self, owned existing: Self):
        self.name = existing.name^
        self.domain = existing.domain^
        self.path = existing.path^

    fn __copyinit__(out self: Self, existing: Self):
        self.name = existing.name
        self.domain = existing.domain
        self.path = existing.path

    fn __hash__[H: Hasher](self, mut hasher: H):
        hasher.update(self.name)
        hasher.update(self.domain)
        hasher.update(self.path)

    fn __str__(self) -> String:
        return self.name + "|" + self.domain + "|" + self.path

    fn write_to[T: Writer](self, mut writer: T):
        writer.write(self.__str__())


struct ResponseCookieJar(Copyable, Movable, Sized, Stringable, Writable):
    var _inner: Dict[ResponseCookieKey, Cookie]

    fn __init__(out self):
        self._inner = Dict[ResponseCookieKey, Cookie]()

    fn __init__(out self, *cookies: Cookie):
        self._inner = Dict[ResponseCookieKey, Cookie]()
        for cookie in cookies:
            self.set_cookie(cookie)

    fn __init__(out self, cookies: List[Cookie]):
        self._inner = Dict[ResponseCookieKey, Cookie]()
        for cookie in cookies:
            self.set_cookie(cookie)

    fn __copyinit__(out self: Self, existing: Self):
        self._inner = existing._inner

    fn __moveinit__(out self: Self, owned existing: Self):
        self._inner = existing._inner^

    @always_inline
    fn __setitem__(mut self, key: ResponseCookieKey, value: Cookie):
        self._inner[key] = value

    fn __getitem__(self, key: ResponseCookieKey) raises -> Cookie:
        return self._inner[key]

    fn get(self, key: ResponseCookieKey) -> Optional[Cookie]:
        try:
            return self[key]
        except:
            return None

    @always_inline
    fn __contains__(self, key: ResponseCookieKey) -> Bool:
        return key in self._inner

    @always_inline
    fn __contains__(self, key: Cookie) -> Bool:
        return ResponseCookieKey(key.name, key.domain, key.path) in self

    fn __str__(self) -> String:
        return to_string(self)

    fn __len__(self) -> Int:
        return len(self._inner)

    @always_inline
    fn set_cookie(mut self, cookie: Cookie):
        self[ResponseCookieKey(cookie.name, cookie.domain, cookie.path)] = cookie

    @always_inline
    fn empty(self) -> Bool:
        return len(self) == 0

    fn from_headers(mut self, headers: List[String]) raises:
        for header in headers:
            try:
                self.set_cookie(Cookie.from_set_header(header[]))
            except:
                raise Error("Failed to parse cookie header string " + String(header))

    fn write_to[T: Writer](self, mut writer: T):
        for cookie in self._inner.values():
            var v = cookie.build_header_value()
            write_header(writer, HeaderKey.SET_COOKIE, v)
