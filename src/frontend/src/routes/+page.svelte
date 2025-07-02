<script>
  import "../index.scss";
  import { backend } from "$lib/canisters";
  import { onMount } from "svelte";

  let did = "";
  let rawJsonText = "";
  let buildRequestLoading = false;
  let verifyRequestLoading = false;
  let buildRequestResult = "";
  let verifyRequestResult = "";
  let verifyRequestSuccess = false;
  let copyButtonState = "copy"; // "copy", "copied", "error"
  let jsonExpanded = false;

  // Initialize section state
  let isInitialized = false;
  let checkingInitialization = false;
  let initializeLoading = false;
  let initializeResult = "";
  let initializeSuccess = false;

  // Initialize form data
  let initDomain = "";
  let initPlcDid = "";
  let initContactEmail = "";

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

  // Initialize section functions
  onMount(async () => {
    await checkInitializationStatus();
  });

  async function checkInitializationStatus() {
    checkingInitialization = true;
    try {
      isInitialized = await backend.isInitialized();
    } catch (error) {
      console.error("Error checking initialization status:", error);
    } finally {
      checkingInitialization = false;
    }
  }

  async function initializePDS() {
    if (!initDomain.trim() || !initPlcDid.trim()) {
      initializeResult = "Error: Domain and PLC DID are required";
      initializeSuccess = false;
      return;
    }

    initializeLoading = true;
    initializeResult = "";

    try {
      // Parse domain - for simplicity, we'll treat the whole input as domain name
      // In a more sophisticated implementation, you might want to parse subdomains
      const domainParts = initDomain.trim().split('.');
      const suffix = domainParts.length > 1 ? domainParts.pop() : "";
      const name = domainParts.join('.');
      
      const serverInfo = {
        domain: {
          name: name,
          subdomains: [],
          suffix: suffix
        },
        plcDid: {
          identifier: initPlcDid.trim()
        },
        contactEmailAddress: initContactEmail.trim() ? [initContactEmail.trim()] : []
      };

      const response = await backend.initialize(serverInfo);
      
      if ("ok" in response) {
        initializeResult = "✅ PDS initialized successfully!";
        initializeSuccess = true;
        isInitialized = true;
        // Clear the form
        initDomain = "";
        initPlcDid = "";
        initContactEmail = "";
      } else {
        initializeResult = `❌ Error: ${response.err}`;
        initializeSuccess = false;
      }
    } catch (error) {
      initializeResult = `❌ Network error: ${error.message}`;
      initializeSuccess = false;
    } finally {
      initializeLoading = false;
    }
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
  <section class="initialize-section">
    <h2>Initialize PDS</h2>
    
    {#if checkingInitialization}
      <div class="status-indicator">
        <p>⏳ Checking initialization status...</p>
      </div>
    {:else if isInitialized}
      <div class="status-indicator success">
        <p>✅ PDS is already initialized and ready to use!</p>
      </div>
    {:else}
      <div class="status-indicator">
        <p>⚠️ PDS needs to be initialized before use</p>
      </div>
      
      <div class="initialize-instructions">
        <h3>Initialization Steps:</h3>
        <ol>
          <li>Use the PLC Directory Integration below to build a PLC request</li>
          <li>Submit the request to plc.directory using the generated cURL command</li>
          <li>Copy the resulting PLC DID from the directory</li>
          <li>Fill in the form below to initialize your PDS</li>
        </ol>
      </div>

      <form class="initialize-form">
        <div class="form-section">
          <h3>Server Information</h3>
          
          <div class="field-group">
            <label for="init-domain">Domain *:</label>
            <input
              id="init-domain"
              type="text"
              bind:value={initDomain}
              placeholder="example.com"
              class="text-input"
              required
            />
            <small>Enter your full domain name (e.g., pds.example.com)</small>
          </div>
          
          <div class="field-group">
            <label for="init-plc-did">PLC DID *:</label>
            <input
              id="init-plc-did"
              type="text"
              bind:value={initPlcDid}
              placeholder="did:plc:..."
              class="text-input"
              required
            />
            <small>Enter the DID you received after submitting to plc.directory</small>
          </div>
          
          <div class="field-group">
            <label for="init-contact-email">Contact Email (optional):</label>
            <input
              id="init-contact-email"
              type="email"
              bind:value={initContactEmail}
              placeholder="admin@example.com"
              class="text-input"
            />
          </div>
        </div>
      </form>

      <div class="button-group">
        <button
          on:click={initializePDS}
          disabled={initializeLoading || !initDomain.trim() || !initPlcDid.trim()}
          class="initialize-button"
        >
          {initializeLoading ? "Initializing..." : "Initialize PDS"}
        </button>
      </div>

      {#if initializeResult}
        <div
          class="result"
          class:success={initializeSuccess}
          class:error={!initializeSuccess}
        >
          <strong>Initialize Result:</strong> {initializeResult}
        </div>
      {/if}
    {/if}
  </section>

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
                  <label for="service-name-{index}">Name:</label>
                  <input
                    id="service-name-{index}"
                    type="text"
                    bind:value={services[index].name}
                    placeholder="Service name"
                    class="text-input"
                  />
                </div>
                <div class="field-group">
                  <label for="service-type-{index}">Type:</label>
                  <input
                    id="service-type-{index}"
                    type="text"
                    bind:value={services[index].type}
                    placeholder="Service type"
                    class="text-input"
                  />
                </div>
                <div class="field-group">
                  <label for="service-endpoint-{index}">Endpoint:</label>
                  <input
                    id="service-endpoint-{index}"
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
