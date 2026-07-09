# twindemo

This is the twin **seat**: `xenodot-twin/` here is a clone of the framework (`github.com/arthur0n/xenodot-twin`), so any framework or tool work that proves out here is committed **inside that clone and pushed to core** — it never stays twindemo-local — while `house/` is only the test viewer and receives framework tools via the materializer (never hand-edit its `tools/`).

Start the framework web UI for this seat on **`PORT=8339`** (`PORT=8339 ./start_server`, door `http://localhost:8339`) — `8338` is the forge seat's port, so never start the twin UI on the default or it kills forge's server.
