defmodule Parsex.Subtitle.Line do
  defstruct(number: nil, start_time: nil, end_time: nil, text: [])
  @type t :: %Parsex.Subtitle.Line{number: Integer.t, start_time: Float.t,
                                  end_time: Float.t, text: List.t}

  def parse_all_lines(file_stream) do
    Enum.chunk_by(file_stream, fn(line) -> line != "\n" end)
    |> ParallelStream.filter(fn(elem) -> elem != ["\n"] end)
    |> Enum.into([])
    |> ParallelStream.map(fn(line) -> parse_line(line) end)
    |> Enum.into([])
    |> ParallelStream.reject(fn(line) -> is_nil(line) end)
    |> Enum.into([])
  end

  def sync_all_lines(lines, sync_time) do
    try do
      ParallelStream.map(lines, fn(line) -> sync_line(line, sync_time) end)
      |> Enum.into([])
    rescue
      _ -> {nil, :error}
    end
  end

  def lines_to_string(lines) do
    ParallelStream.map(lines, fn(line)->
      "#{line.number}\n" <>
      "#{seconds_to_timestamp(line.start_time)} --> " <>
      "#{seconds_to_timestamp(line.end_time)}\n" <>
      "#{Enum.join(line.text, "\n")}\n"
    end)
    |> Enum.into([])
    |> Enum.join("\n")
  end

  def timestamp_to_seconds(time) do
    [_, h, m, s, ms] = Regex.run(~r/(?<h>\d+):(?<m>\d+):(?<s>\d+)[,.](?<ms>\d+)/, time)
    (String.to_integer(h) * 3600)
    |> Kernel.+((String.to_integer(m)) * 60)
    |> Kernel.+(String.to_float("#{s}.#{ms}"))
  end

  def seconds_to_timestamp(seconds) do
    [sec_int, decimal] = Float.to_string(seconds, [decimals: 3])
    |> String.split(".")
    |> ParallelStream.map(fn(elem) -> String.to_integer(elem) end)
    |> Enum.into([])
    h = round(Float.floor(seconds / 3600)) |> append_zero()
    m = round(Float.floor(rem(sec_int, 3600) / 60)) |> append_zero()
    s = rem(sec_int , 60) |> append_zero()
    ms = decimal |> append_zero(:ms)

    "#{h}:#{m}:#{s},#{ms}"
  end

  def unescape_line(line) do
    ParallelStream.map(line, fn(text) ->
      text = String.replace(text, ~r/\n|\t|\r/, "")
      :iconv.convert("ISO-8859-1", "UTF-8", text)
    end)
    |> Enum.into([])
  end

  def format_timestamp(timestamp) do
    timestamp = String.split(timestamp, " --> ")
    start_time = List.first(timestamp) |> timestamp_to_seconds
    end_time = List.last(timestamp) |> timestamp_to_seconds
    %{start_time: start_time, end_time: end_time}
  end

  def append_zero(number, type \\ :normal) do
    case type do
      :ms ->
        String.rjust(to_string(number), 3, ?0)
      _ ->
        String.rjust(to_string(number), 2, ?0)
    end
  end

  def parse_line(line) do
    line = unescape_line(line)
    try do
      line_number = Enum.at(line, 0) |> String.to_integer()
      timestamp = Enum.at(line, 1) |> format_timestamp
      texts = Enum.drop(line, 2)

      %Parsex.Subtitle.Line{
        number: line_number,
        start_time: timestamp.start_time,
        end_time: timestamp.end_time,
        text: texts
      }
    rescue
      _ -> nil
    end
  end

  def sync_line(line, sync_time) do
    {operator, parsed_sync_time} = parse_sync_time(sync_time)
    start_time = line.start_time
    end_time = line.end_time
    {start_time, end_time} = case operator do
      "+" ->
        {start_time + parsed_sync_time, end_time + parsed_sync_time}
      "-" ->
        {start_time - parsed_sync_time, end_time - parsed_sync_time}
      _ -> nil
    end
    line
    |> Map.put(:start_time, start_time)
    |> Map.put(:end_time, end_time)
  end

  def parse_sync_time(sync_time) do
    instances = %{"ms" => 0.001, "s" => 1, "m" => 60, "h" => 3600}

    case String.match?(sync_time, ~r/([+-])([.,0-9]+)(ms|s|m|h)/) do
      nil -> {nil, :error}
      _ ->
        try do
          [_, operator, time, time_instance] = Regex.run(~r/([+-])([.,0-9]+)(ms|s|m|h)/, sync_time)
          time_to_add = elem(Float.parse(time), 0) * instances[time_instance]
          {operator, time_to_add}
        rescue
          _ -> {nil, :error}
        end
    end
  end
end
