module Gluten = Dream_gluten.Gluten
module Gluten_eio = Dream_gluten_eio.Gluten_eio
module Httpaf = Dream_httpaf_.Httpaf
module Httpaf_eio = Dream_httpaf__eio.Httpaf_eio
module H2 = Dream_h2.H2
module H2_eio = Dream_h2_eio.H2_eio
module Catch = Dream__server.Catch
module Error_template = Dream__server.Error_template
module Helpers = Dream__server.Helpers
module Log = Dream__server.Log
module Random = Dream__cipher.Random
module Router = Dream__server.Router
module Query = Dream__server.Query
module Cookie = Dream__server.Cookie
module Tag = Dream__server.Tag
include Dream_pure
include Method
include Status
include Log

let to_dream_method meth =
  Httpaf.Method.to_string meth |> Method.string_to_method

let to_httpaf_status status =
  Status.status_to_int status |> Httpaf.Status.of_code

let to_h2_status status = Status.status_to_int status |> H2.Status.of_code

module Wrap = struct
  (* Wraps the user's Dream handler in the kind of handler expected by http/af.
     The scheme is simple: wait for http/af "Reqd.t"s (partially parsed
     connections), convert their fields to Dream.request, call the user's handler,
     wait for the Dream.response, and then convert it to an http/af Response and
     sned it.

     If the user's handler (wrongly) leaks any exceptions or rejections, they are
     passed to http/af to end up in the error handler. This is a low-level handler
     that ordinarily shouldn't be relied on by the user - this is just our last
     chance to tell the user that something is wrong with their app. *)
  (* TODO Rename conn like in the body branch. *)
  let wrap_handler tls (user's_error_handler : Catch.error_handler)
      (user's_dream_handler : Message.handler) =
    let httpaf_request_handler client_address (conn : _ Gluten.Reqd.t) =
      let conn, upgrade = (conn.reqd, conn.upgrade) in

      (* Covert the http/af request to a Dream request. *)
      let httpaf_request : Httpaf.Request.t = Httpaf.Reqd.request conn in

      let method_ = to_dream_method httpaf_request.meth in
      let target = httpaf_request.target in
      let headers = Httpaf.Headers.to_list httpaf_request.headers in

      let body = Httpaf.Reqd.request_body conn in
      (* TODO Review per-chunk allocations. *)
      (* TODO Should the stream be auto-closed? It doesn't even have a closed
         state. The whole thing is just a wrapper for whatever the http/af
         behavior is. *)
      let read ~data ~flush:_ ~ping:_ ~pong:_ ~close ~exn:_ =
        Httpaf.Body.Reader.schedule_read body
          ~on_eof:(fun () -> close 1000)
          ~on_read:(fun buffer ~off ~len -> data buffer off len true false)
      in
      let close _code = Httpaf.Body.Reader.close body in
      let body = Stream.reader ~read ~close ~abort:close in
      let body = Stream.stream body Stream.no_writer in

      let request : Message.request =
        Helpers.request ~client:"(TODO)" ~method_ ~target ~tls ~headers body
      in

      (* Call the user's handler. If it raises an exception or returns a promise
         that rejects with an exception, pass the exception up to Httpaf. This
         will cause it to call its (low-level) error handler with variand `Exn _.
         A well-behaved Dream app should catch all of its own exceptions and
         rejections in one of its top-level middlewares.

         We don't try to log exceptions here because the behavior is not
         customizable here. The handler itself is customizable (to catch all)
         exceptions, and the error callback that gets leaked exceptions is also
         customizable. *)
      begin
        try
          (* Do the big call. *)
          let response = user's_dream_handler request in

          (* Extract the Dream response's headers. *)

          (* This is the default function that translates the Dream response to an
             http/af response and sends it. We pre-define the function, however,
             because it is called from two places:

             1. Upon a normal response, the function is called unconditionally.
             2. Upon failure to establish a WebSocket, the function is called to
                transmit the resulting error response. *)
          let forward_response response =
            Message.set_content_length_headers response;

            let headers =
              Httpaf.Headers.of_list (Message.all_headers response)
            in

            let status = to_httpaf_status (Message.status response) in

            let httpaf_response = Httpaf.Response.create ~headers status in
            let body =
              Httpaf.Reqd.respond_with_streaming conn httpaf_response
            in

            Adapt.forward_body response body
          in

          match Message.get_websocket response with
          | None -> forward_response response
          | Some (client_stream, _server_stream) ->
            (* let's not support websockets at first*)
            assert false
        with exn ->
          (* TODO There was something in the fork changelogs about not requiring
             report exn. Is it relevant to this? *)
          Httpaf.Reqd.report_exn conn exn
      end
    in

    httpaf_request_handler

  (* TODO Factor out what is in common between the http/af and h2 handlers. *)
  let wrap_handler_h2 tls (_user's_error_handler : Catch.error_handler)
      (user's_dream_handler : Message.handler) =
    let httpaf_request_handler client_address (conn : H2.Reqd.t) =
      (* Covert the h2 request to a Dream request. *)
      let httpaf_request : H2.Request.t = H2.Reqd.request conn in

      let method_ = to_dream_method httpaf_request.meth in
      let target = httpaf_request.target in
      let headers = H2.Headers.to_list httpaf_request.headers in

      let body = H2.Reqd.request_body conn in
      let read ~data ~flush:_ ~ping:_ ~pong:_ ~close ~exn:_ =
        H2.Body.Reader.schedule_read body
          ~on_eof:(fun () -> close 1000)
          ~on_read:(fun buffer ~off ~len -> data buffer off len true false)
      in
      let close _code = H2.Body.Reader.close body in
      let body = Stream.reader ~read ~close ~abort:close in
      let body = Stream.stream body Stream.no_writer in

      let request : Message.request =
        Helpers.request ~client:"(todo)" ~method_ ~target ~tls ~headers body
      in

      (* Call the user's handler. If it raises an exception or returns a promise
         that rejects with an exception, pass the exception up to Httpaf. This
         will cause it to call its (low-level) error handler with variand `Exn _.
         A well-behaved Dream app should catch all of its own exceptions and
         rejections in one of its top-level middlewares.

         We don't try to log exceptions here because the behavior is not
         customizable here. The handler itself is customizable (to catch all)
         exceptions, and the error callback that gets leaked exceptions is also
         customizable. *)
      begin
        try
          (* Do the big call. *)
          let response = user's_dream_handler request in

          Logs.info (fun f ->
              f "Got response: %s"
                (Eio.Promise.await_exn (Message.body response)));

          (* Extract the Dream response's headers. *)
          let forward_response response =
            Message.drop_content_length_headers response;
            Message.lowercase_headers response;
            let headers = H2.Headers.of_list (Message.all_headers response) in
            let status = to_h2_status (Message.status response) in
            let h2_response = H2.Response.create ~headers status in
            let body = H2.Reqd.respond_with_streaming conn h2_response in

            Adapt.forward_body_h2 response body
          in

          match Message.get_websocket response with
          | None -> forward_response response
          | Some _ ->
            (* TODO DOC H2 appears not to support WebSocket upgrade at present.
               RFC 8441. *)
            (* TODO DOC Do we need a CONNECT method? Do users need to be informed of
               this? *)
            ()
        with exn ->
          (* TODO LATER There was something in the fork changelogs about not
             requiring report_exn. Is it relevant to this? *)
          H2.Reqd.report_exn conn exn
      end
    in

    httpaf_request_handler
end

module Pclock = struct
  let clock : Eio.Time.clock option ref = ref None

  let now_d_ps () =
    match !clock with
    | None -> failwith "clock wasn't set up"
    | Some clock ->
      let t = clock#now in
      let days = t /. 86_400. in
      let remainder = t -. (days *. 86_400.) in
      (Float.to_int days, Int64.of_float (remainder *. 1_000_000_000_000.))

  let current_tz_offset_s () = None

  (* https://github.com/mirage/mirage-clock/blob/main/solo5/pclock.ml *)
  let period_d_ps () = Some (0, 1_000_000L)
end

include Log.Make (Pclock)
include Dream__server.Echo

let default_log = Log.sub_log (Logs.Src.name Logs.default)
let error = default_log.error
let warning = default_log.warning
let info = default_log.info
let debug = default_log.debug

module Session = struct
  include Dream__server.Session
  include Dream__server.Session.Make (Pclock)
end

module Flash = Dream__server.Flash
include Dream__server.Origin_referrer_check
include Dream__server.Form
include Dream__server.Upload
include Dream__server.Csrf
include Dream__server.Catch
include Dream__server.Site_prefix

let error_template = Error_handler.customize

(*
let random =
  Dream__cipher.Random.random
*)
include Formats

(* Types *)

type request = Message.request
type response = Message.response
type handler = Message.handler
type middleware = Message.middleware
type route = Router.route
type 'a message = 'a Message.message
type client = Message.client
type server = Message.server

(* Requests *)

let body_stream = Message.server_stream
let client = Helpers.client
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
let stream = Helpers.stream
let status = Message.status
let read = Message.read
let write = Message.write
let flush = Message.flush

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

let body = Message.body
let set_body = Message.set_body
let close = Message.close

type buffer = Stream.buffer
type stream = Stream.stream

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

(* websockets *)

type websocket = stream * stream

let websocket = Helpers.websocket

type text_or_binary =
  [ `Text
  | `Binary ]

type end_of_message =
  [ `End_of_message
  | `Continues ]

let send = Helpers.send
let receive = Helpers.receive
let receive_fragment = Helpers.receive_fragment
let close_websocket = Message.close_websocket

(* Middleware *)

let no_middleware = Message.no_middleware
let pipeline = Message.pipeline

(* Routing *)

let router (r : route list) : handler = Router.router r
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

(* Sessions *)

let session = Session.session
let put_session = Session.put_session
let all_session_values = Session.all_session_values
let invalidate_session = Session.invalidate_session
let memory_sessions = Session.memory_sessions
let cookie_sessions = Session.cookie_sessions
let session_id = Session.session_id
let session_label = Session.session_label
let session_expires_at = Session.session_expires_at

(* Flash messages *)

let flash_messages = Flash.flash_messages
let flash = Flash.flash
let put_flash = Flash.put_flash
let log = Log.convenience_log
let now () = Ptime.to_float_s (Ptime.v (Pclock.now_d_ps ()))
let form = form ~now
let multipart = multipart ~now
let csrf_token = csrf_token ~now
let verify_csrf_token = verify_csrf_token ~now
let csrf_tag = Tag.csrf_tag ~now

(* Templates *)

let form_tag ?method_ ?target ?enctype ?csrf_token ~action request =
  Tag.form_tag ~now ?method_ ?target ?enctype ?csrf_token ~action request

(* Errors *)

type error = Catch.error = {
  condition : [`Response of Message.response | `String of string | `Exn of exn];
  layer : [`App | `HTTP | `HTTP2 | `TLS | `WebSocket];
  caused_by : [`Server | `Client];
  request : Message.request option;
  response : Message.response option;
  client : string option;
  severity : Log.log_level;
  will_send_response : bool;
}

type error_handler = Catch.error_handler

(*   let error_template = Error_handler.customize *)
let catch = Catch.catch

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

let built_in_middleware prefix error_handler =
  Message.pipeline
    [
      Dream__server.Catch.catch (Error_handler.app error_handler);
      Dream__server.Site_prefix.with_site_prefix prefix;
    ]

let localhost_certificate =
  let crts =
    Rresult.R.failwith_error_msg
      (X509.Certificate.decode_pem_multiple
         (Cstruct.of_string Dream__certificate.localhost_certificate))
  in
  let key =
    Rresult.R.failwith_error_msg
      (X509.Private_key.decode_pem
         (Cstruct.of_string Dream__certificate.localhost_certificate_key))
  in
  `Single (crts, key)

open Dream_httpaf__eio

let https ~port ?(prefix = "") env
    ?(cfg =
      Tls.Config.server ~alpn_protocols:["http/1.1"]
        ~certificates:localhost_certificate ())
    ?error_handler:(user's_error_handler : error_handler =
        Error_handler.default) (user's_dream_handler : Message.handler) =
  initialize ~setup_outputs:ignore;
  Pclock.clock := Some env#clock;
  Mirage_crypto_rng_eio.run (module Mirage_crypto_rng.Fortuna) env @@ fun () ->
  Eio.Switch.run @@ fun sw ->
  let socket =
    Eio.Net.listen ~backlog:10 ~sw env#net
      (`Tcp
        ( Eio.Net.Ipaddr.of_raw Ipaddr.V4.(of_string_exn "0.0.0.0" |> to_octets),
          port ))
  in
  let handler conn' socket =
    let conn = Tls_eio.server_of_flow cfg conn' in
    let epoch = Tls_eio.epoch conn |> Result.get_ok in
    Eio.traceln "HANDLER %s"
      (epoch.alpn_protocol |> Option.value ~default:"(none)");
    match epoch.alpn_protocol with
    | Some "h2" ->
      Logs.err (fun f -> f "!!");
      H2_eio.Server.create_connection_handler
        ~request_handler:
          (Wrap.wrap_handler_h2 false user's_error_handler user's_dream_handler)
        ~error_handler:(Error_handler.h2 user's_error_handler)
        socket
        (conn :> Eio.Flow.two_way);
      Logs.err (fun f -> f "??");
      Eio.traceln "OK";
      conn#shutdown `All;
      conn'#shutdown `All;
      Eio.traceln "closed"
    | _ ->
      Httpaf_eio.Server.create_connection_handler
        ~request_handler:
          (Wrap.wrap_handler false user's_error_handler user's_dream_handler)
        ~error_handler:(Error_handler.httpaf user's_error_handler)
        socket
        (conn :> Eio.Flow.two_way)
  in
  while true do
    Eio.Net.accept_fork ~sw socket ~on_error:(fun _ -> ()) handler
  done

let http ~port ?(prefix = "") ?(protocol = `HTTP_1_1) env
    ?error_handler:(user's_error_handler = Error_handler.default)
    user's_dream_handler =
  initialize ~setup_outputs:ignore;
  Pclock.clock := Some env#clock;
  Eio.Switch.run @@ fun sw ->
  let socket =
    Eio.Net.listen ~backlog:10 ~sw env#net
      (`Tcp
        ( Eio.Net.Ipaddr.of_raw Ipaddr.V4.(of_string_exn "0.0.0.0" |> to_octets),
          port ))
  in
  let f =
    Httpaf_eio.Server.create_connection_handler
      ~request_handler:
        (Wrap.wrap_handler false user's_error_handler user's_dream_handler)
      ~error_handler:(Error_handler.httpaf user's_error_handler)
  in
  let handler conn socket = f socket (conn :> Eio.Flow.two_way) in
  while true do
    Eio.Net.accept_fork ~sw socket ~on_error:(fun _ -> ()) handler
  done

let validate_path request =
  let path = Dream__server.Router.path request in

  let has_slash component = String.contains component '/' in
  let has_backslash component = String.contains component '\\' in
  let has_slash = List.exists has_slash path in
  let has_backslash = List.exists has_backslash path in
  let has_dot = List.exists (( = ) Filename.current_dir_name) path in
  let has_dotdot = List.exists (( = ) Filename.parent_dir_name) path in
  let has_empty = List.exists (( = ) "") path in
  let is_empty = path = [] in

  if
    has_slash || has_backslash || has_dot || has_dotdot || has_empty || is_empty
  then
    None
  else
    let path = String.concat Filename.dir_sep path in
    if Filename.is_relative path then
      Some path
    else
      None

(* Static files *)

let mime_lookup filename =
  let content_type =
    match Magic_mime.lookup filename with
    | "text/html" -> Formats.text_html
    | content_type -> content_type
  in
  [("Content-Type", content_type)]

let static ~loader local_root request =
  if not @@ Method.methods_equal (Message.method_ request) `GET then
    Message.response ~status:`Not_Found Stream.empty Stream.null
  else
    match validate_path request with
    | None -> Message.response ~status:`Not_Found Stream.empty Stream.null
    | Some path ->
      let response = loader local_root path request in
      if not (Message.has_header response "Content-Type") then begin
        match Message.status response with
        | `OK
        | `Non_Authoritative_Information
        | `No_Content
        | `Reset_Content
        | `Partial_Content ->
          Message.add_header response "Content-Type" (Magic_mime.lookup path)
        | _ -> ()
      end;
      response
