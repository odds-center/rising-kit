import Foundation

/// 인터넷 뱅킹용 보안 프로그램(키보드 보안, 인증서 모듈 등)의 백그라운드 항목을 다룬다.
/// 프로그램을 지우지 않고, launchd 에 등록된 항목을 내렸다가 다시 올리기만 한다.
public enum BankSecurity {
    public struct Job: Equatable {
        public let label: String
        public let plistPath: String
        /// true 면 시스템 전체(관리자 권한 필요), false 면 로그인한 사용자 몫
        public let isSystem: Bool

        public init(label: String, plistPath: String, isSystem: Bool) {
            self.label = label; self.plistPath = plistPath; self.isSystem = isSystem
        }

        /// 사람이 알아볼 이름
        public var vendor: String { BankSecurity.vendorName(for: label) }
    }

    /// 이름표(label)에 이 조각이 들어 있으면 은행 보안 프로그램으로 본다.
    /// 일반 백신(V3 등)을 끄지 않도록 AhnLab 은 금융 거래용 ASTx 만 넣었다.
    private static let patterns: [(fragment: String, name: String)] = [
        ("ahnlab.astx", "AhnLab Safe Transaction"),
        ("com.astx.", "AhnLab Safe Transaction"),   // 실제 이름표는 com.astx.firewall.* 이다
        ("nprotect", "nProtect Online Security"),
        ("wizvera.veraport", "Veraport"),
        ("wizvera.delfino", "Delfino"),
        ("raon.touchen", "TouchEn nxKey"),
        ("raon.agent.touchen", "TouchEn nxKey"),
        ("raon.touchen_teweb", "TouchEn Web"),
        ("raonwiz.raonk", "Raon K"),
        ("interezen", "IPinside"),
        ("iniline.crossex", "CrossEX"),
        ("initech", "INISAFE CrossWeb"),
        ("dreamsecurity.magicline", "MagicLine4NX"),
        ("softforum.anysign", "AnySign"),
        ("crosscert", "UniSign"),
        ("unisign", "UniSign"),
    ]

    public static func isSecurityJob(label: String) -> Bool {
        let lower = label.lowercased()
        return patterns.contains { lower.contains($0.fragment) }
    }

    public static func vendorName(for label: String) -> String {
        let lower = label.lowercased()
        return patterns.first { lower.contains($0.fragment) }?.name ?? label
    }

    /// 셸 명령에 그대로 넣어도 안전한 이름·경로인지 (공백·따옴표·특수문자가 없는 것만 다룬다).
    public static func isSafe(_ job: Job) -> Bool {
        let labelOK = !job.label.isEmpty && job.label.allSatisfy { $0.isLetter || $0.isNumber || "._-".contains($0) }
        let pathOK = job.plistPath.hasPrefix("/") && job.plistPath.hasSuffix(".plist")
            && job.plistPath.allSatisfy { $0.isLetter || $0.isNumber || "/._-".contains($0) }
        return labelOK && pathOK
    }

    /// 항목들을 끄거나 켜는 셸 명령. `uid` 는 로그인한 사용자의 번호.
    /// 끄기: 다음 로그인·재시동에도 꺼져 있도록 표시(disable)한 뒤 내린다(bootout).
    /// 켜기: 표시를 풀고(enable) 다시 올린다(bootstrap).
    public static func commands(for jobs: [Job], turnOn: Bool, uid: Int) -> [String] {
        jobs.filter(isSafe).flatMap { job -> [String] in
            let domain = job.isSystem ? "system" : "gui/\(uid)"
            if turnOn {
                return ["/bin/launchctl enable \(domain)/\(job.label)",
                        "/bin/launchctl bootstrap \(domain) \(job.plistPath)"]
            }
            return ["/bin/launchctl disable \(domain)/\(job.label)",
                    "/bin/launchctl bootout \(domain)/\(job.label)"]
        }
    }
}
