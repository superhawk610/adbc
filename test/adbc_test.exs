defmodule AdbcTest do
  use ExUnit.Case, async: true
  doctest Adbc

  alias Adbc.{Database, Connection}

  describe "download_driver" do
    test "multiple times" do
      assert Adbc.download_driver(:sqlite) == :ok
      assert Adbc.download_driver(:sqlite) == :ok
    end

    test "returns errors" do
      assert {:error, "unknown driver :unknown, expected one of :sqlite, :postgresql, " <> _} =
               Adbc.download_driver(:unknown)
    end
  end

  describe "postgresql smoke tests" do
    @describetag :postgresql

    test "runs queries" do
      db =
        start_supervised!(
          {Database, driver: :postgresql, uri: "postgres://postgres:postgres@localhost"}
        )

      conn = start_supervised!({Connection, database: db})

      assert {:ok, %Adbc.Result{data: %{"num" => [123]}}} =
               Connection.query(conn, "SELECT 123 as num")
    end
  end

  describe "duckdb smoke tests" do
    @describetag :duckdb
    @duckdb_version "0.8.1"

    setup do
      {target, executable} =
        case :os.type() do
          {:unix, :darwin} -> {"libduckdb-osx-universal", "libduckdb.dylib"}
          {:unix, _} -> {"libduckdb-linux-amd64", "libduckdb.so"}
        end

      tmp_dir = System.tmp_dir!()
      cache_path = Path.join(tmp_dir, "#{target}-v#{@duckdb_version}.zip")

      unless File.regular?(cache_path) do
        {:ok, zip_data} =
          Adbc.Helper.download(
            "https://github.com/duckdb/duckdb/releases/download/v#{@duckdb_version}/#{target}.zip",
            false
          )

        File.write!(cache_path, zip_data)
      end

      cache_path = String.to_charlist(cache_path)
      {:ok, zip_handle} = :zip.zip_open(cache_path, [:memory])
      {:ok, zip_files} = :zip.table(cache_path)

      for {:zip_file, filename, _, _, _, _} <- zip_files,
          Path.extname(filename) in [".so", ".dylib"] do
        {:ok, {filename, file_data}} = :zip.zip_get(filename, zip_handle)

        filename = to_string(filename)

        filepath = Path.join(tmp_dir, filename)
        File.write!(filepath, file_data)
      end

      :ok = :zip.zip_close(zip_handle)
      %{path: Path.join(tmp_dir, executable), entrypoint: "duckdb_adbc_init"}
    end

    test "starts a database", %{path: path, entrypoint: entrypoint} do
      assert {:ok, _} = Database.start_link(driver: path, entrypoint: entrypoint)

      assert {:error, %Adbc.Error{} = error} =
               Database.start_link(driver: path, entrypoint: "entrypoint")

      assert Exception.message(error) =~ "dlsym(entrypoint) failed:"
    end
  end
end
