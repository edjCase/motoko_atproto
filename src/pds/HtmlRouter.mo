import ServerInfoHandler "./Handlers/ServerInfoHandler";
import RouteContext "mo:liminal@3/RouteContext";
import Route "mo:liminal@3/Route";
import Text "mo:core@1/Text";
import DID "mo:did@3";

module {

  public class Router(
    serverInfoHandler : ServerInfoHandler.Handler
  ) = this {

    public func getLandingPage(routeContext : RouteContext.RouteContext) : Route.HttpResponse {
      let serverInfo = serverInfoHandler.get();
      let landingPageHtml = "<!DOCTYPE html>
<html lang=\"en\">
<head>
    <meta charset=\"UTF-8\">
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
    <title>ATProto PDS for DAOs</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: 'Courier New', monospace;
            background: #0a0a0a;
            color: #00ff00;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
            line-height: 1.6;
        }
        .terminal {
            background: #000;
            border: 2px solid #00ff00;
            border-radius: 8px;
            box-shadow: 0 0 20px rgba(0, 255, 0, 0.3), inset 0 0 50px rgba(0, 255, 0, 0.05);
            padding: 40px;
            max-width: 800px;
            width: 100%;
        }
        .prompt {
            color: #00ff00;
            margin-bottom: 5px;
        }
        .prompt:before {
            content: \"$ \";
            color: #00ff00;
        }
        h1 {
            font-size: 2rem;
            margin-bottom: 30px;
            color: #00ff00;
            text-shadow: 0 0 10px rgba(0, 255, 0, 0.5);
        }
        .section {
            margin-bottom: 30px;
        }
        .links-section {
            padding-bottom: 20px;
            margin-bottom: 30px;
            border-bottom: 1px dashed #00ff00;
        }
        .section-title {
            color: #00ff00;
            font-weight: bold;
            margin-bottom: 10px;
            text-decoration: underline;
        }
        p {
            margin-bottom: 15px;
            color: #00dd00;
        }
        .highlight {
            color: #00ff00;
            font-weight: bold;
        }
        a {
            color: #00ff00;
            text-decoration: none;
            border-bottom: 1px solid #00ff00;
            transition: all 0.3s;
        }
        a:hover {
            color: #fff;
            border-bottom-color: #fff;
            text-shadow: 0 0 5px rgba(0, 255, 0, 0.8);
        }
        .footer {
            margin-top: 40px;
            padding-top: 20px;
            border-top: 1px solid #00ff00;
            font-size: 0.9rem;
            color: #00aa00;
        }
        .blink {
            animation: blink 1s infinite;
        }
        @keyframes blink {
            0%, 50% { opacity: 1; }
            51%, 100% { opacity: 0; }
        }
        @media (max-width: 600px) {
            .terminal {
                padding: 30px 20px;
            }
            h1 {
                font-size: 1.5rem;
            }
        }
    </style>
</head>
<body>
    <div class=\"terminal\">
        <h1>ATProto PDS for DAOs<span class=\"blink\">_</span></h1>

        <div class=\"section links-section\">
            <p class=\"prompt\">Quick Links</p>
            <p>
                Atmosphere: at://{HANDLE}<br>
                BluSky Profile: <a href=\"https://bsky.app/profile/{HANDLE}\" target=\"_blank\">bsky.app/profile/{HANDLE}</a><br>
                DID: <span class=\"highlight\">{PLC_DID}</span> (<a href=\"https://web.plc.directory/did/did:plc:74xe6ejv6k4c7amqb7pef3os\" target=\"_blank\">Directory</a>)<br>
            </p>
        </div>

        <div class=\"section\">
            <p class=\"section-title\">&gt; What is ATProto?</p>
            <p>
                AT Protocol is a decentralized social networking protocol that lets you own your identity and data.
                A <span class=\"highlight\">Personal Data Server (PDS)</span> hosts your social content, posts, and profile—giving you
                control over your online presence independent of any single platform.
            </p>
        </div>

        <div class=\"section\">
            <p class=\"section-title\">&gt; Why DAOs?</p>
            <p>
                This PDS implementation is designed for <span class=\"highlight\">DAO-controlled accounts</span>.
                Instead of individual ownership, your organization can collectively manage an ATProto presence—posting
                announcements, building reputation, and participating in decentralized social networks through
                on-chain governance.
            </p>
        </div>

        <div class=\"section\">
            <p class=\"section-title\">&gt; Use Cases</p>
            <p>
                → Decentralized brand accounts with collective control<br>
                → Transparent organizational communications<br>
                → DAO-governed social media presence<br>
                → Community-driven content curation
            </p>
        </div>

        <div class=\"footer\">
            <p class=\"prompt\">Open source implementation in Motoko</p>
            <p><a href=\"https://github.com/edjCase/motoko_atproto\" target=\"_blank\">github.com/edjCase/motoko_atproto</a></p>
        </div>
    </div>
</body>
</html>"
      |> Text.replace(_, #text("{HANDLE}"), serverInfo.hostname)
      |> Text.replace(_, #text("{PLC_DID}"), DID.Plc.toText(serverInfo.plcIdentifier));

      routeContext.buildResponse(#ok, #html(landingPageHtml));
    };
  };
};
