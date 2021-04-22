LoggerJsonFileBackend
===

LoggerJsonFileBackend is elixir `logger` backend that writes json logs to a file.

Configuration
---

This logger backend provides follow options:

| name              | description |
| ----------------- | ----------- |
| path              | log file path. this option is "MUST" |
| level             | minimum logging level. default is `:info` |
| metadata          | included metadata keys list. detault is empty list |
| metadata_filter   | metadata terms which must be present in order to log, for example: [status: 404]. detault is empty list |
| metadata\_triming | if false, ignoring previous metadata options and all metadata are output. default is true. It is recommended true in production environment. |
| json\_encoder     | using json encoder. default [jason](https://github.com/michalmuskala/jason) |
| uuid              | If true, add uuid field to record. Default is false. |

You need to add logger backend setting

```elixir
config :logger,
  backends: [{LoggerJSONFileBackend, :log_name}]

config :logger, :log_name,
  path: "/var/log/my_app/app.log",
  level: :info,
  metadata: [:request_id, :user_id, :method, :path, :req_params],
  metadata_filter: [status: 404],
  json_encoder: Poison, # default is Jason
  uuid: true
```

Use case
---

This module is assumed to be used with a custom plug logger.

Example 1:

```elixir
Logger.info("request", [
  method:     conn.method,
  path:       conn.request_path,
  req_params: conn.params,
])
```

Example 2:

```elixir
Logger.error("not found", [
  method:     conn.method,
  path:       conn.request_path,
  req_params: conn.params,
  status:     404
])
```
