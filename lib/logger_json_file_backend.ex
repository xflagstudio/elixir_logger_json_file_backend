defmodule LoggerJSONFileBackend do
  @behaviour :gen_event

  @macro_env_fields [:pid] ++ Map.keys(%Macro.Env{})
  @formatter if Version.compare(System.version(), "1.6.0") == :lt, do: Logger.Utils, else: Logger.Formatter

  @impl :gen_event
  def init({__MODULE__, name}) do
    {:ok, configure(name, [])}
  end

  @impl :gen_event
  def handle_call({:configure, opts}, %{name: name} = state) do
    {:ok, :ok, configure(name, opts, state)}
  end

  @impl :gen_event
  def handle_call(:path, %{path: path} = state) do
    {:ok, {:ok, path}, state}
  end

  @impl :gen_event
  def handle_event({level, _gl, {Logger, msg, ts, md}}, %{level: min_level, metadata_filter: metadata_filter}=state) do
    if (is_nil(min_level) or Logger.compare_levels(level, min_level) != :lt) and metadata_matches?(md, metadata_filter) do
      log_event(level, msg, ts, md, state)
    else
      {:ok, state}
    end
  end

  @impl :gen_event
  def handle_event(:flush, state) do
    {:ok, state}
  end

  @impl :gen_event
  def handle_info(_msg, state) do
    {:ok, state}
  end

  @impl :gen_event
  def terminate(_reason, _state) do
    :ok
  end

  @impl :gen_event
  def code_change(_old, state, _extra) do
    {:ok, state}
  end

  defp log_event(level, msg, ts, md, %{path: path, io_device: nil}=state) when is_binary(path) do
    case open_log(path) do
      {:ok, io_device, inode} ->
        log_event(level, msg, ts, md, %{state | io_device: io_device, inode: inode})
      _other ->
        {:ok, state}
    end
  end

  defp log_event(level, msg, ts, md, %{path: path, io_device: io_device, inode: inode, metadata: keys, json_encoder: json_encoder, triming: triming, uuid: uuid}=state) when is_binary(path) do
    if !is_nil(inode) and inode == inode(path) do
      message = case uuid do
        true ->
          json_encoder.encode!(Map.merge(%{level: level, uuid: UUID.uuid4(), message: (msg |> IO.iodata_to_binary), time: format_time(ts)}, take_metadata(md, keys, triming))) <> "\n"
        false ->
          json_encoder.encode!(Map.merge(%{level: level, message: (msg |> IO.iodata_to_binary), time: format_time(ts)}, take_metadata(md, keys, triming))) <> "\n"
      end
      IO.write(io_device, message)
      {:ok, state}
    else
      File.close(io_device)
      log_event(level, msg, ts, md, %{state | io_device: nil, inode: nil})
    end
  end

  defp format_time({date, time}) do
    [@formatter.format_date(date), @formatter.format_time(time)]
    |> Enum.map(&IO.iodata_to_binary/1)
    |> Enum.join(" ")
  end

  defp take_metadata(metadata, _keys, false) do
    reject_keys = @macro_env_fields
    metadata |> Keyword.drop(reject_keys) |> Enum.into(%{})
  end
  defp take_metadata(metadata, keys, true) do
    List.foldr keys, %{}, fn key, acc ->
      case Keyword.fetch(metadata, key) do
        {:ok, val} ->
          if key == :pid do
            Map.merge(acc, %{key => inspect(val)})
          else
            Map.merge(acc, %{key => val})
          end
        :error     -> acc
      end
    end
  end

  defp open_log(path) do
    case (path |> Path.dirname |> File.mkdir_p) do
      :ok ->
        case File.open(path, [:append, :utf8]) do
          {:ok, io_device} ->
            {:ok, io_device, inode(path)}
          other -> other
        end
      other -> other
    end
  end

  defp inode(path) do
    case File.stat(path) do
      {:ok, %File.Stat{inode: inode}} -> inode
      {:error, _} -> nil
    end
  end

  @doc false
  @spec metadata_matches?(Keyword.t, nil|Keyword.t) :: true|false
  def metadata_matches?(_md, nil), do: true
  def metadata_matches?(_md, []), do: true # all of the filter keys are present
  def metadata_matches?(md, [{key, val}|rest]) do
    case Keyword.fetch(md, key) do
      {:ok, ^val} ->
        metadata_matches?(md, rest)
      _ -> false #fail on first mismatch
    end
  end

  defp configure(name, opts) do
    state = %{name: nil, path: nil, io_device: nil, inode: nil, level: nil, metadata: nil, metadata_filter: nil, json_encoder: nil, triming: false, uuid: false}
    configure(name, opts, state)
  end

  defp configure(name, opts, state) do
    env = Application.get_env(:logger, name, [])
    opts = Keyword.merge(env, opts)
    Application.put_env(:logger, name, opts)

    level           = Keyword.get(opts, :level, :info)
    metadata        = Keyword.get(opts, :metadata, [])
    metadata_filter = Keyword.get(opts, :metadata_filter)
    path            = Keyword.get(opts, :path)
    json_encoder    = Keyword.get(opts, :json_encoder, Jason)
    triming         = Keyword.get(opts, :metadata_triming, true)
    uuid            = Keyword.get(opts, :uuid, false)

    %{state | name: name, path: path, level: level, metadata: metadata, metadata_filter: metadata_filter, json_encoder: json_encoder, triming: triming, uuid: uuid}
  end
end
