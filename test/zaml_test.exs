defmodule ZamlTest do
  use ExUnit.Case

  test "loads simple map" do
    assert Zaml.load("a: 1\nb: hello\n") == %{"a" => 1, "b" => "hello"}
  end

  test "parses nested structures" do
    yaml = """
    name: example
    count: 42
    ratio: 3.14
    flag: true
    empty: ~
    list:
      - 1
      - 2
      - 3
    nested:
      a: 1
      b: 2
    """

    result = Zaml.load(yaml)
    assert result["name"] == "example"
    assert result["count"] == 42
    assert result["ratio"] == 3.14
    assert result["flag"] == true
    assert result["empty"] == nil
    assert result["list"] == [1, 2, 3]
    assert result["nested"] == %{"a" => 1, "b" => 2}
  end

  test "handles explicit tags" do
    assert Zaml.load("x: !!str 123") == %{"x" => "123"}
    assert Zaml.load("x: !!int \"42\"") == %{"x" => 42}
  end

  test "returns :nil for empty" do
    assert Zaml.load("") == nil
  end

  @tag :skip
  test "parses anchors" do
    yaml = """
    defaults: &defaults
      a: 1
      b: 2
    prod:
      <<: *defaults
      c: 3
    """

    result = Zaml.load(yaml)
    assert result["prod"]["a"] == 1
    assert result["prod"]["b"] == 2
    assert result["prod"]["c"] == 3
  end

  test "returns :parse_error for bad input" do
    # Unbalanced braces are an error.
    assert Zaml.load("[unclosed") in [:parse_error, :error]
  end
end
