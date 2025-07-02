<script>
  import "../index.scss";
  import { backend } from "$lib/canisters";

  let did = "";
  let rawJsonText = "";
  let buildRequestLoading = false;
  let verifyRequestLoading = false;
  let buildRequestResult = "";
  let verifyRequestResult = "";
  let verifyRequestSuccess = false;
  let copyButtonState = "copy"; // "copy", "copied", "error"
  let jsonExpanded = false;

  // Form data for buildPlcRequest
  let alsoKnownAs = [""];
  let services = [
    {
      name: "atproto_pds",
      type: "AtprotoPersonalDataServer",
      endpoint: "",
    },
  ];

  function addAlsoKnownAs() {
    alsoKnownAs = [...alsoKnownAs, ""];
  }

  function removeAlsoKnownAs(index) {
    alsoKnownAs = alsoKnownAs.filter((_, i) => i !== index);
  }

  function addService() {
    services = [...services, { name: "", type: "", endpoint: "" }];
  }

  function removeService(index) {
    services = services.filter((_, i) => i !== index);
  }

  async function buildPlcRequest() {
    buildRequestLoading = true;
    buildRequestResult = "";
    verifyRequestResult = ""; // Clear verify result

    try {
      // Filter out empty alsoKnownAs entries
      const filteredAlsoKnownAs = alsoKnownAs.filter(
        (item) => item.trim() !== ""
      );

      // Filter out incomplete services
      const filteredServices = services.filter(
        (service) =>
          service.name.trim() !== "" &&
          service.type.trim() !== "" &&
          service.endpoint.trim() !== ""
      );

      const requestData = {
        alsoKnownAs: filteredAlsoKnownAs,
        services: filteredServices,
      };

      const response = await backend.buildPlcRequest(requestData);
      console.log("PLC request response:", response);

      if ("ok" in response) {
        const [didValue, jsonValue] = response.ok;
        did = didValue;
        rawJsonText = jsonValue;
        buildRequestResult = "PLC request built successfully!";
      } else {
        buildRequestResult = `Error: ${response.err}`;
        did = "";
        rawJsonText = "";
      }
    } catch (error) {
      buildRequestResult = `Error: ${error.message}`;
      did = "";
      rawJsonText = "";
    } finally {
      buildRequestLoading = false;
    }
  }

  async function verifyPlcDirectory() {
    if (!did) {
      verifyRequestResult = "Error: No DID available. Build request first.";
      verifyRequestSuccess = false;
      return;
    }

    verifyRequestLoading = true;
    verifyRequestResult = "";
    buildRequestResult = ""; // Clear build result

    try {
      const response = await fetch(`https://plc.directory/${did}`, {
        method: "GET",
      });

      if (response.ok) {
        verifyRequestResult = `✅ DID found on plc.directory! The request was successfully submitted.`;
        verifyRequestSuccess = true;
      } else if (response.status === 404) {
        verifyRequestResult = `❌ DID not found on plc.directory. The request may not have been submitted yet or failed.`;
        verifyRequestSuccess = false;
      } else {
        verifyRequestResult = `⚠️ Error checking plc.directory: ${response.status} ${response.statusText}`;
        verifyRequestSuccess = false;
      }
    } catch (error) {
      verifyRequestResult = `❌ Network error checking plc.directory: ${error.message}`;
      verifyRequestSuccess = false;
    } finally {
      verifyRequestLoading = false;
    }
  }

  async function copyCurlCommand() {
    const curlCommand = `curl -X POST https://plc.directory/${did} \\
  -H "Content-Type: application/json" \\
  -d '${rawJsonText}'`;

    try {
      await navigator.clipboard.writeText(curlCommand);
      copyButtonState = "copied";

      // Reset button state after 2 seconds
      setTimeout(() => {
        copyButtonState = "copy";
      }, 2000);
    } catch (err) {
      console.error("Failed to copy: ", err);
      copyButtonState = "error";

      // Reset button state after 2 seconds
      setTimeout(() => {
        copyButtonState = "copy";
      }, 2000);
    }
  }
</script>

<main>
  <section class="plc-section">
    <h2>PLC Directory Integration</h2>

    <form class="plc-form">
      <div class="form-section">
        <h3>Also Known As</h3>
        <div class="dynamic-list">
          {#each alsoKnownAs as item, index}
            <div class="list-item">
              <input
                type="text"
                bind:value={alsoKnownAs[index]}
                placeholder="Enter alias or domain"
                class="text-input"
              />
              <button
                type="button"
                class="remove-button"
                on:click={() => removeAlsoKnownAs(index)}
                disabled={alsoKnownAs.length <= 1}
              >
                ❌
              </button>
            </div>
          {/each}
          <button type="button" class="add-button" on:click={addAlsoKnownAs}>
            ➕ Add Also Known As
          </button>
        </div>
      </div>

      <div class="form-section">
        <h3>Services</h3>
        <div class="dynamic-list">
          {#each services as service, index}
            <div class="service-item">
              <div class="service-fields">
                <div class="field-group">
                  <label>Name:</label>
                  <input
                    type="text"
                    bind:value={services[index].name}
                    placeholder="Service name"
                    class="text-input"
                  />
                </div>
                <div class="field-group">
                  <label>Type:</label>
                  <input
                    type="text"
                    bind:value={services[index].type}
                    placeholder="Service type"
                    class="text-input"
                  />
                </div>
                <div class="field-group">
                  <label>Endpoint:</label>
                  <input
                    type="url"
                    bind:value={services[index].endpoint}
                    placeholder="https://example.com"
                    class="text-input"
                  />
                </div>
              </div>
              <button
                type="button"
                class="remove-button"
                on:click={() => removeService(index)}
                disabled={services.length <= 1}
              >
                ❌
              </button>
            </div>
          {/each}
          <button type="button" class="add-button" on:click={addService}>
            ➕ Add Service
          </button>
        </div>
      </div>
    </form>

    <div class="button-group">
      <button
        on:click={buildPlcRequest}
        disabled={buildRequestLoading}
        class="build-button"
      >
        {buildRequestLoading ? "Building..." : "Build PLC Request"}
      </button>

      <button
        on:click={verifyPlcDirectory}
        disabled={verifyRequestLoading || !did}
        class="verify-button"
      >
        {verifyRequestLoading ? "Verifying..." : "Verify on PLC Directory"}
      </button>
    </div>

    {#if buildRequestResult || verifyRequestResult}
      <div
        class="result"
        class:build-result={buildRequestResult && !verifyRequestResult}
        class:verify-result={verifyRequestResult}
        class:success={verifyRequestSuccess}
        class:error={verifyRequestResult && !verifyRequestSuccess}
      >
        {#if verifyRequestResult}
          <strong>Verify Result:</strong> {verifyRequestResult}
        {:else if buildRequestResult}
          <strong>Build Result:</strong> {buildRequestResult}
        {/if}
      </div>
    {/if}

    {#if did && rawJsonText}
      <div class="request-data">
        <h3>Generated Request Data:</h3>
        <div class="data-field">
          <strong>DID:</strong> <code>{did}</code>
        </div>

        <div class="curl-section">
          <div class="curl-header">
            <h4>cURL Command:</h4>
            <button
              class="copy-button"
              class:copied={copyButtonState === "copied"}
              class:error={copyButtonState === "error"}
              on:click={copyCurlCommand}
              title="Copy to clipboard"
              disabled={copyButtonState !== "copy"}
            >
              {#if copyButtonState === "copied"}
                ✅ Copied!
              {:else if copyButtonState === "error"}
                ❌ Failed
              {:else}
                📋 Copy
              {/if}
            </button>
          </div>
          <div class="curl-container">
            <pre class="curl-command">curl -X POST https://plc.directory/{did} \
  -H "Content-Type: application/json" \
  -d '{rawJsonText}'</pre>
          </div>
        </div>

        <div class="json-section">
          <div class="json-header">
            <h4>Raw JSON:</h4>
            <button
              class="toggle-button"
              on:click={() => (jsonExpanded = !jsonExpanded)}
              title={jsonExpanded ? "Collapse JSON" : "Expand JSON"}
            >
              {jsonExpanded ? "🔽 Collapse" : "▶️ Expand"}
            </button>
          </div>
          {#if jsonExpanded}
            <div class="json-container">
              <pre class="json-preview">{JSON.stringify(
                  JSON.parse(rawJsonText),
                  null,
                  2
                )}</pre>
            </div>
          {/if}
        </div>
      </div>
    {/if}
  </section>
</main>
