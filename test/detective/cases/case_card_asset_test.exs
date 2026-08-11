defmodule Detective.Cases.CaseCardAssetTest do
  use ExUnit.Case, async: true

  @asset_root Path.expand("../../../assets/public/images/cards/dcoa", __DIR__)
  @metadata Path.join(@asset_root, "source.json")

  test "official fan-case kit supplies one physical card back for every A-L slot" do
    backs =
      @asset_root
      |> Path.join("backs/*.webp")
      |> Path.wildcard()
      |> Enum.sort()

    assert Enum.map(backs, &Path.basename(&1, ".webp")) ==
             Enum.flat_map(?a..?l, fn code ->
               [<<code, "-220">>, <<code>>, <<code, "@2x">>]
             end)

    Enum.each(backs, fn path ->
      assert <<"RIFF", _size::little-32, "WEBP", _rest::binary>> = File.read!(path)
    end)

    Enum.each(?a..?l, fn code ->
      standard = Path.join(@asset_root, "backs/#{<<code>>}.webp")
      compact = Path.join(@asset_root, "backs/#{<<code>>}-220.webp")
      retina = Path.join(@asset_root, "backs/#{<<code>>}@2x.webp")

      assert File.stat!(compact).size < File.stat!(standard).size
      assert File.stat!(retina).size > File.stat!(standard).size
    end)
  end

  test "records publisher provenance and keeps runtime card assets local" do
    metadata = @metadata |> File.read!() |> Jason.decode!()

    assert metadata["publisher"] == "Van Ryder Games"
    assert metadata["project_use"] == "public_non_commercial_fan_project"
    assert metadata["runtime_derivatives"]["format"] == "webp"
    assert metadata["runtime_derivatives"]["variants"]["standard"]["width"] == 420
    assert metadata["runtime_derivatives"]["variants"]["compact"]["width"] == 220
    assert metadata["runtime_derivatives"]["variants"]["compact"]["suffix"] == "-220.webp"
    assert metadata["runtime_derivatives"]["variants"]["standard"]["quality"] == 88
    assert metadata["runtime_derivatives"]["variants"]["zoom"]["suffix"] == "@2x.webp"
    assert metadata["runtime_derivatives"]["variants"]["zoom"]["width"] == 675

    assert Enum.all?(metadata["runtime_derivatives"]["paths"], fn path ->
             String.starts_with?(path, "/images/cards/dcoa/")
           end)

    Enum.each(
      ~w(faces/female-business faces/truncheon faces/bloody-ropes templates/suspect templates/evidence templates/information),
      fn relative_path ->
        standard = Path.join(@asset_root, relative_path <> ".webp")
        compact = Path.join(@asset_root, relative_path <> "-220.webp")
        retina = Path.join(@asset_root, relative_path <> "@2x.webp")

        assert File.exists?(compact)
        assert File.exists?(standard)
        assert File.exists?(retina)
        assert File.stat!(compact).size < File.stat!(standard).size
        assert File.stat!(retina).size > File.stat!(standard).size
      end
    )
  end
end
