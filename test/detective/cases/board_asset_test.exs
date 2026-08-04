defmodule Detective.Cases.BoardAssetTest do
  use ExUnit.Case, async: true

  @asset Path.expand("../../../assets/public/images/maps/dcoa/game-board-final.png", __DIR__)
  @metadata Path.expand("../../../assets/public/images/maps/dcoa/source.json", __DIR__)

  test "official board asset matches recorded non-commercial provenance" do
    metadata = @metadata |> File.read!() |> Jason.decode!()

    digest =
      @asset |> File.read!() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)

    assert metadata["source_url"] ==
             "https://vanrydergames.com/cdn/shop/files/GameBoard_FINAL_069e54c3-3406-4bd3-9589-1fe30dee505f.png?v=1717096238"

    assert metadata["project_use"] == "public_non_commercial_fan_project"
    assert metadata["width"] == 1000
    assert metadata["height"] == 636
    assert metadata["sha256"] == digest
    assert digest == "9cb4b980b6b5a4567315aca2ab82e276f50dc403febcabd806e249672a74c61b"
  end
end
