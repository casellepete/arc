defmodule Arc.Actions.Store do
  defmacro __using__(_) do
    quote do
      def store(args), do: Arc.Actions.Store.store(__MODULE__, args)
      def aws_opts_store(aws_opts, args), do: Arc.Actions.Store.aws_opts_store(__MODULE__, aws_opts, args)
    end
  end

  
  def aws_opts_store(definition, aws_opts, {file, scope}) when is_binary(file) or is_map(file) do
    put(definition, aws_opts, {Arc.File.new(file), scope})
  end

  def aws_opts_store(definition, aws_opts, filepath) when is_binary(filepath) or is_map(filepath) do
    aws_opts_store(definition, aws_opts, {filepath, nil})
  end

  
  def store(definition, {file, scope}) when is_binary(file) or is_map(file) do
    put(definition, [], {Arc.File.new(file), scope})
  end

  def store(definition, filepath) when is_binary(filepath) or is_map(filepath) do
    store(definition, {filepath, nil})
  end



  #
  # Private
  #

  defp put(_definition, aws_opts, { error = {:error, _msg}, _scope}), do: error
  defp put(definition, aws_opts, {%Arc.File{}=file, scope}) do
    case definition.validate({file, scope}) do
      true -> put_versions(definition, aws_opts, {file, scope})
      _    -> {:error, :invalid_file}
    end
  end

  defp put_versions(definition, aws_opts, {file, scope}) do
    if definition.async do
      definition.__versions
      |> Enum.map(fn(r)    -> async_put_version(definition, aws_opts, r, {file, scope}) end)
      |> Enum.map(fn(task) -> Task.await(task, version_timeout()) end)
      |> handle_responses(file.file_name)
    else
      definition.__versions
      |> Enum.map(fn(version) -> put_version(definition, aws_opts, version, {file, scope}) end)
      |> handle_responses(file.file_name)
    end
  end

  defp handle_responses(responses, filename) do
    errors = Enum.filter(responses, fn(resp) -> elem(resp, 0) == :error end) |> Enum.map(fn(err) -> elem(err, 1) end)
    if Enum.empty?(errors), do: {:ok, filename}, else: {:error, errors}
  end

  defp version_timeout do
    Application.get_env(:arc, :version_timeout) || 15_000
  end

  defp async_put_version(definition, aws_opts, version, {file, scope}) do
    Task.async(fn ->
      put_version(definition, aws_opts, version, {file, scope})
    end)
  end

  defp put_version(definition, aws_opts, version, {file, scope}) do
    case Arc.Processor.process(definition, version, {file, scope}) do
      {:error, error} -> {:error, error}
      {:ok, file} ->
        file_name = Arc.Definition.Versioning.resolve_file_name(definition, version, {file, scope})
        file      = %Arc.File{file | file_name: file_name}
        definition.__storage.put(definition, aws_opts, version, {file, scope})
    end
  end
end
