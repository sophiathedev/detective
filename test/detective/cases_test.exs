defmodule Detective.CasesTest do
  use Detective.DataCase, async: true

  import Detective.CasesFixtures

  alias Detective.Cases

  test "lists only published versions of published cases" do
    published = case_version_fixture()

    draft_case = case_file_fixture(status: "draft")
    _draft_version = case_version_fixture(case_file: draft_case)

    unpublished = case_version_fixture(published_at: nil)

    ids = Enum.map(Cases.list_published_versions(), & &1.id)

    assert published.id in ids
    refute unpublished.id in ids
    assert length(ids) == 1
  end
end
