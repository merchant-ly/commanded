defmodule Commanded.Event.EventHandlerStopAfterTest do
  use Commanded.MockEventStoreCase

  alias Commanded.Event.EchoHandler
  alias Commanded.Event.ReplyEvent
  alias Commanded.Helpers.EventFactory

  defp reply_to, do: :erlang.pid_to_list(self())

  defp make_events(count) do
    Enum.map(1..count, fn _ -> %ReplyEvent{reply_to: reply_to()} end)
  end

  defp send_events_to_handler(handler, events, initial_event_number \\ 1) do
    recorded_events = EventFactory.map_to_recorded_events(events, initial_event_number)
    send(handler, {:events, recorded_events})
  end

  describe "stop_after_event" do
    test "handler stops after reaching the target event" do
      handler = start_supervised!(EchoHandler)
      ref = Process.monitor(handler)

      assert {:ok, nil} = GenServer.call(handler, {:stop_after_event, 5})

      events = make_events(7)
      send_events_to_handler(handler, Enum.take(events, 4), 1)
      send_events_to_handler(handler, Enum.drop(events, 4), 5)

      for event <- Enum.take(events, 5) do
        assert_receive {:event, ^handler, ^event, _metadata}
      end

      event6 = Enum.at(events, 5)
      event7 = Enum.at(events, 6)
      refute_receive {:event, ^handler, ^event6, _metadata}
      refute_receive {:event, ^handler, ^event7, _metadata}

      assert_receive {:DOWN, ^ref, :process, ^handler, :normal}
    end

    test "handler already past target stops immediately" do
      handler = start_supervised!(EchoHandler)
      ref = Process.monitor(handler)

      events = make_events(5)
      send_events_to_handler(handler, events)

      for event <- events do
        assert_receive {:event, ^handler, ^event, _metadata}
      end

      assert {:ok, 5} = GenServer.call(handler, {:stop_after_event, 3})

      assert_receive {:DOWN, ^ref, :process, ^handler, :normal}
    end

    test "handler hasn't received any events yet" do
      handler = start_supervised!(EchoHandler)
      ref = Process.monitor(handler)

      assert {:ok, nil} = GenServer.call(handler, {:stop_after_event, 10})

      events = make_events(10)
      send_events_to_handler(handler, events)

      for event <- events do
        assert_receive {:event, ^handler, ^event, _metadata}
      end

      assert_receive {:DOWN, ^ref, :process, ^handler, :normal}
    end

    test "handler stops after target when events arrive in a single batch" do
      handler = start_supervised!(EchoHandler)
      ref = Process.monitor(handler)

      assert {:ok, nil} = GenServer.call(handler, {:stop_after_event, 3})

      events = make_events(5)
      send_events_to_handler(handler, events)

      for event <- Enum.take(events, 3) do
        assert_receive {:event, ^handler, ^event, _metadata}
      end

      event4 = Enum.at(events, 3)
      event5 = Enum.at(events, 4)
      refute_receive {:event, ^handler, ^event4, _metadata}
      refute_receive {:event, ^handler, ^event5, _metadata}

      assert_receive {:DOWN, ^ref, :process, ^handler, :normal}
    end
  end

  describe "handoff" do
    test "executes callback with current position" do
      handler = start_supervised!(EchoHandler)

      events = make_events(5)
      send_events_to_handler(handler, events)

      for event <- events do
        assert_receive {:event, ^handler, ^event, _metadata}
      end

      assert {:ok, 10} = GenServer.call(handler, {:handoff, fn pos -> pos * 2 end})

      Process.exit(handler, :kill)
    end

    test "callback can interact with other processes" do
      handler = start_supervised!(EchoHandler)

      events = make_events(3)
      send_events_to_handler(handler, events)

      for event <- events do
        assert_receive {:event, ^handler, ^event, _metadata}
      end

      test_pid = self()

      assert {:ok, :sent} =
               GenServer.call(handler, {
                 :handoff,
                 fn _pos ->
                   send(test_pid, :from_handoff)
                   :sent
                 end
               })

      assert_receive :from_handoff
      assert Process.alive?(handler)

      Process.exit(handler, :kill)
    end
  end
end
