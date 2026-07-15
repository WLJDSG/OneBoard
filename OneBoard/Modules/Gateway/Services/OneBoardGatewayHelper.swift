import Foundation

struct OneBoardGatewayHelper {
    static let helperPath = "/usr/local/bin/oneboard-gateway-helper"
    static let sudoersPath = "/etc/sudoers.d/oneboard-gateway"
    static let allowedIPsPath = "/etc/oneboard-gateway-allowed-ips.conf"
    static let versionMarker = "ONEBOARD_GATEWAY_HELPER_VERSION=2"

    private let runner: GatewayCommandRunning
    private let fileManager: FileManager

    init(
        runner: GatewayCommandRunning = ProcessGatewayCommandRunner(),
        fileManager: FileManager = .default
    ) {
        self.runner = runner
        self.fileManager = fileManager
    }

    func isInstalled() -> Bool {
        guard fileManager.isExecutableFile(atPath: Self.helperPath),
              let script = try? String(contentsOfFile: Self.helperPath, encoding: .utf8) else {
            return false
        }
        return Self.isCurrentHelperScript(script)
    }

    static func isCurrentHelperScript(_ script: String) -> Bool {
        script.contains(versionMarker)
    }

    func install() throws {
        let script = Self.installShellScript(helperBody: Self.helperBody)
        try runAdminShell(script)
    }

    func uninstall() throws {
        try runAdminShell([
            "/bin/rm -f \(Self.helperPath.shellQuoted)",
            "/bin/rm -f \(Self.sudoersPath.shellQuoted)",
            "/bin/rm -f \(Self.allowedIPsPath.shellQuoted)"
        ].joined(separator: "; "))
    }

    func syncWhitelist(ips: [String]) throws {
        let uniqueIPs = Array(Set(ips.filter(GatewayProfile.isValidIPv4))).sorted()
        let result = try runner.run(
            "/usr/bin/sudo",
            arguments: ["-n", Self.helperPath, "--sync-whitelist", uniqueIPs.joined(separator: ",")]
        )
        guard result.terminationStatus == 0 else {
            let message = [result.standardError, result.standardOutput]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? "OneBoard 网关白名单同步失败"
            throw GatewayError.commandFailed(message)
        }
    }

    private func runAdminShell(_ shellCommand: String) throws {
        let appleScript = "do shell script \(shellCommand.appleScriptQuoted) with administrator privileges"
        let result = try runner.run("/usr/bin/osascript", arguments: ["-e", appleScript])
        guard result.terminationStatus == 0 else {
            let message = [result.standardError, result.standardOutput]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? "OneBoard 网关 helper 操作失败"
            throw GatewayError.commandFailed(message)
        }
    }

    private static func installShellScript(helperBody: String) -> String {
        let sudoers = "\(NSUserName()) ALL=(root) NOPASSWD: \(helperPath)\n"
        return [
            "/bin/mkdir -p /usr/local/bin",
            "/usr/bin/printf %s \(helperBody.shellQuoted) > \(helperPath.shellQuoted)",
            "/bin/chmod 755 \(helperPath.shellQuoted)",
            "/usr/bin/printf %s \(sudoers.shellQuoted) > \(sudoersPath.shellQuoted)",
            "/bin/chmod 440 \(sudoersPath.shellQuoted)",
            "/usr/bin/touch \(allowedIPsPath.shellQuoted)",
            "/bin/chmod 644 \(allowedIPsPath.shellQuoted)"
        ].joined(separator: "; ")
    }

    private static let helperBody = """
#!/bin/sh
set -eu
ONEBOARD_GATEWAY_HELPER_VERSION=2

ALLOWED_FILE="/etc/oneboard-gateway-allowed-ips.conf"
SERVICE=""
IP=""
SUBNET=""
ROUTER=""
DNS=""
SYNC_WHITELIST=""
SYNC_MODE=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --service) SERVICE="$2"; shift 2 ;;
    --ip) IP="$2"; shift 2 ;;
    --subnet) SUBNET="$2"; shift 2 ;;
    --router) ROUTER="$2"; shift 2 ;;
    --dns) DNS="$2"; shift 2 ;;
    --sync-whitelist) SYNC_WHITELIST="$2"; SYNC_MODE=1; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

is_valid_ipv4() {
  /usr/bin/awk -F. '
    NF != 4 { exit 1 }
    { for (i = 1; i <= 4; i++) if ($i !~ /^[0-9]+$/ || $i < 0 || $i > 255) exit 1 }
  ' <<EOF
$1
EOF
}

if [ "$SYNC_MODE" -eq 1 ]; then
  TEMP_FILE="${ALLOWED_FILE}.tmp.$$"
  : > "$TEMP_FILE"
  OLD_IFS="$IFS"
  IFS=","
  for address in $SYNC_WHITELIST; do
    [ -n "$address" ] || continue
    is_valid_ipv4 "$address" || { /bin/rm -f "$TEMP_FILE"; echo "Invalid whitelist IP: $address" >&2; exit 3; }
    /usr/bin/printf '%s\n' "$address" >> "$TEMP_FILE"
  done
  IFS="$OLD_IFS"
  /bin/chmod 644 "$TEMP_FILE"
  /bin/mv -f "$TEMP_FILE" "$ALLOWED_FILE"
  exit 0
fi

is_allowed_ip() {
  [ -f "$ALLOWED_FILE" ] || return 1
  /usr/bin/grep -Fxq "$1" "$ALLOWED_FILE"
}

[ -n "$SERVICE" ] || { echo "Missing service" >&2; exit 2; }
[ -n "$DNS" ] || { echo "Missing DNS" >&2; exit 2; }

OLD_IFS="$IFS"
IFS=","
for server in $DNS; do
  is_allowed_ip "$server" || { echo "DNS is not allowed: $server" >&2; exit 3; }
done
IFS="$OLD_IFS"
DNS_ARGS="$(/bin/echo "$DNS" | /usr/bin/tr ',' ' ')"

if [ -n "$ROUTER" ]; then
  is_allowed_ip "$ROUTER" || { echo "Router is not allowed: $ROUTER" >&2; exit 3; }
  [ -n "$IP" ] || { echo "Missing IP" >&2; exit 2; }
  [ -n "$SUBNET" ] || { echo "Missing subnet" >&2; exit 2; }
  /usr/sbin/networksetup -setmanual "$SERVICE" "$IP" "$SUBNET" "$ROUTER"
fi

/usr/sbin/networksetup -setdnsservers "$SERVICE" $DNS_ARGS
if [ -n "$ROUTER" ]; then
  /sbin/route -n change default "$ROUTER" || /sbin/route -n add default "$ROUTER"
fi
/usr/bin/dscacheutil -flushcache
/usr/bin/killall -HUP mDNSResponder || true
"""
}
