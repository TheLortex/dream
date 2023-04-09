(* This file is part of Dream, released under the MIT license. See LICENSE.md
   for details, or visit https://github.com/aantron/dream.

   Copyright 2021 Anton Bachin *)



module Catch = Dream__server.Catch
module Cipher = Dream__cipher.Cipher
module Cookie = Dream__server.Cookie
module Csrf = Dream__server.Csrf
module Echo = Dream__server.Echo
module Error_handler = Dream__http.Error_handler
module Flash = Dream__server.Flash
module Form = Dream__server.Form
module Formats = Dream_pure.Formats
module Graphql = Dream__graphql.Graphql
module Helpers = Dream__server.Helpers
module Http = Dream__http.Http
module Message = Dream_pure.Message
module Method = Dream_pure.Method
module Origin_referrer_check = Dream__server.Origin_referrer_check
module Query = Dream__server.Query
module Random = Dream__cipher.Random
module Router = Dream__server.Router
module Site_prefix = Dream__server.Site_prefix
module Sql = Dream__sql.Sql
module Sql_session = Dream__sql.Session
module Static = Dream__unix.Static
module Status = Dream_pure.Status
module Stream = Dream_pure.Stream
module Tag = Dream__server.Tag
module Upload = Dream__server.Upload



(* Initialize clock handling and random number generator. These are
   platform-specific, differing between Unix and Mirage. This is the Unix
   initialization. *)

module Log =
struct
  include Dream__server.Log
  include Dream__server.Log.Make (Ptime_clock)
end

let default_log =
  Log.sub_log (Logs.Src.name Logs.default)

let () =
  Log.initialize ~setup_outputs:Fmt_tty.setup_std_outputs

let now () =
  Ptime.to_float_s (Ptime.v (Ptime_clock.now_d_ps ()))

let mirage_crypto_run env =
  Mirage_crypto_rng_eio.run (module Mirage_crypto_rng.Fortuna) env

module Session =
struct
  include Dream__server.Session
  include Dream__server.Session.Make (Ptime_clock)
end



(* Types *)

type request = Message.request
type response = Message.response
type handler = Message.handler
type middleware = Message.middleware
type route = Router.route

type 'a message = 'a Message.message
type client = Message.client
type server = Message.server



(* Methods *)

include Method



(* Status codes *)

include Status



(* Requests *)

let client = Helpers.client
let tls = Helpers.tls
let method_ = Message.method_
let target = Message.target
let prefix = Router.prefix
let path = Router.path
let set_client = Helpers.set_client
let set_method_ = Message.set_method_
let query = Query.query
let queries = Query.queries
let all_queries = Query.all_queries



(* Responses *)

let response = Helpers.response_with_body
let respond = Helpers.respond
let html = Helpers.html
let json = Helpers.json
let redirect = Helpers.redirect
let empty = Helpers.empty
let status = Message.status
let set_status = Message.set_status



(* Headers *)

let header = Message.header
let headers = Message.headers
let all_headers = Message.all_headers
let has_header = Message.has_header
let add_header = Message.add_header
let drop_header = Message.drop_header
let set_header = Message.set_header



(* Cookies *)

let set_cookie = Cookie.set_cookie
let drop_cookie = Cookie.drop_cookie
let cookie = Cookie.cookie
let all_cookies = Cookie.all_cookies



(* Bodies *)

let body x = Message.body x
let set_body = Message.set_body



(* Streams *)

type stream = Stream.stream
let body_stream = Message.server_stream
let stream = Helpers.stream
let read = Message.read
let write = Message.write
let flush = Message.flush
let close = Message.close
type buffer = Stream.buffer
let client_stream = Message.client_stream
let server_stream = Message.server_stream
let set_client_stream = Message.set_client_stream
let set_server_stream = Message.set_server_stream
let read_stream = Stream.read
let write_stream = Stream.write
let flush_stream = Stream.flush
let ping_stream = Stream.ping
let pong_stream = Stream.pong
let close_stream = Stream.close
let abort_stream = Stream.abort



(* WebSockets *)

type websocket = stream * stream
let websocket = Helpers.websocket
type text_or_binary = [ `Text | `Binary ]
type end_of_message = [ `End_of_message | `Continues ]
let send = Helpers.send
let receive = Helpers.receive
let receive_fragment = Helpers.receive_fragment
let close_websocket = Message.close_websocket



(* JSON *)

let origin_referrer_check = Origin_referrer_check.origin_referrer_check



(* Forms *)

type 'a form_result = 'a Form.form_result
let form ?csrf x = Form.form ~now ?csrf x
type multipart_form = Upload.multipart_form
let multipart ?csrf x = Upload.multipart ~now ?csrf x
type part = Upload.part
let upload request = Upload.upload request
let upload_part request = Upload.upload_part request
type csrf_result = Csrf.csrf_result
let csrf_token = Csrf.csrf_token ~now
let verify_csrf_token = Csrf.verify_csrf_token ~now



(* Templates *)

let form_tag ?method_ ?target ?enctype ?csrf_token ~action request =
  Tag.form_tag ~now ?method_ ?target ?enctype ?csrf_token ~action request

let csrf_tag = Tag.csrf_tag ~now


(* Middleware *)

let no_middleware = Message.no_middleware
let pipeline = Message.pipeline



(* Routing *)

let router = Router.router
let get = Router.get
let post = Router.post
let put = Router.put
let delete = Router.delete
let head = Router.head
let connect = Router.connect
let options = Router.options
let trace = Router.trace
let patch = Router.patch
let any = Router.any
let not_found = Helpers.not_found
let param = Router.param
let scope = Router.scope
let no_route = Router.no_route



(* Static files *)

let static = Static.static
let from_filesystem = Static.from_filesystem
let mime_lookup = Static.mime_lookup



(* Sessions *)
(* TODO Internalize argument order and name changes. *)

let session = Session.session
let session_field request name = session name request
let put_session = Session.put_session
let set_session_field request name value = put_session name value request
let all_session_values = Session.all_session_values
let all_session_fields = all_session_values
let invalidate_session = Session.invalidate_session
let memory_sessions = Session.memory_sessions
let cookie_sessions = Session.cookie_sessions
let sql_sessions = Sql_session.sql_sessions
let session_id = Session.session_id
let session_label = Session.session_label
let session_expires_at = Session.session_expires_at



(* Flash messages *)
(* TODO Internalize argument order and name changes. *)

let flash = Flash.flash_messages
let flash_messages = Flash.flash
let put_flash = Flash.put_flash
let add_flash_message = Flash.put_flash



(* GraphQL *)

let graphql = Graphql.graphql
let graphiql = Graphql.graphiql



(* SQL *)

let sql_pool = Sql.sql_pool
let sql req fn = Sql.sql req fn



(* Logging *)

let logger = Log.logger
let log = Log.convenience_log
type ('a, 'b) conditional_log = ('a, 'b) Log.conditional_log
type log_level = Log.log_level
let error = default_log.error
let warning = default_log.warning
let info = default_log.info
let debug = default_log.debug
type sub_log = Log.sub_log = {
  error : 'a. ('a, unit) conditional_log;
  warning : 'a. ('a, unit) conditional_log;
  info : 'a. ('a, unit) conditional_log;
  debug : 'a. ('a, unit) conditional_log;
}
let sub_log = Log.sub_log
let initialize_log = Log.initialize_log
let set_log_level = Log.set_log_level



(* Errors *)

type error = Catch.error = {
  condition : [
    | `Response of Message.response
    | `String of string
    | `Exn of exn
  ];
  layer : [
    | `App
    | `HTTP
    | `HTTP2
    | `TLS
    | `WebSocket
  ];
  caused_by : [
    | `Server
    | `Client
  ];
  request : Message.request option;
  response : Message.response option;
  client : string option;
  severity : Log.log_level;
  will_send_response : bool;
}
type error_handler = Catch.error_handler
let error_template = Error_handler.customize
let debug_error_handler = Error_handler.debug_error_handler
let catch = Catch.catch



(* Servers *)

let run = Http.run
let serve = Http.serve
let with_site_prefix = Site_prefix.with_site_prefix



(* Web formats *)

include Formats



(* Cryptography *)

let set_secret = Cipher.set_secret
let random = Random.random
let encrypt = Cipher.encrypt
let decrypt = Cipher.decrypt



(* Custom fields *)

type 'a field = 'a Message.field
let new_field = Message.new_field
let field = Message.field
let set_field = Message.set_field



(* Testing. *)

let request = Helpers.request_with_body

(* TODO Restore the ability to test with a prefix and re-enable the
   corresponding tests. *)
let test ?(prefix = "") handler request =
  let app =
    Site_prefix.with_site_prefix prefix
    @@ handler
  in

  let result = ref None in
  Eio_main.run (fun _env ->
      result := Some (app request)
    );
  Option.get !result

let sort_headers = Message.sort_headers
let echo = Echo.echo



(* Deprecated helpers. *)

let with_client client message =
  Helpers.set_client message client;
  message

let with_method_ method_ message =
  Message.set_method_ message method_;
  message

let with_path path message =
  Router.set_path message path;
  message

let with_header name value message =
  Message.set_header message name value;
  message

let with_body body message =
  Message.set_body message body;
  message

let with_stream message =
  message

let write_buffer ?(offset = 0) ?length message chunk =
  let length =
    match length with
    | Some length -> length
    | None -> Bigstringaf.length chunk - offset
  in
  let string = Bigstringaf.substring chunk ~off:offset ~len:length in
  write (Message.server_stream message) string

type 'a local = 'a Message.field
let new_local = Message.new_field
let local = Message.field

let with_local key value message =
  Message.set_field message key value;
  message

let first message =
  message

let last message =
  message
