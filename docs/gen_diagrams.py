"""Generate architecture-<env>.svg for each environment from its terraform.tfvars.

Usage (repo root): python docs/gen_diagrams.py
"""
import re
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent

HEAD = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 750">
<style>
text{fill:#1b2330;font-size:12px;font-family:"IBM Plex Sans",Arial,sans-serif}
.mono{font-family:Consolas,"IBM Plex Mono",monospace;font-size:11px}
.mut{fill:#5a6577}.lbl{font-size:11px;font-family:Consolas,monospace;fill:#5a6577}
.warn{fill:#c2410c}
</style>
<rect width="1000" height="750" fill="#ffffff"/>
<defs>
<marker id="ar" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="#1b2330"/></marker>
<marker id="ara" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="#c2410c"/></marker>
</defs>"""


ANIM_CSS = """
.flow-o{stroke-dasharray:7 5;animation:flow 0.9s linear infinite}
.flow-k{stroke-dasharray:7 5;animation:flow 1.2s linear infinite}
@keyframes flow{to{stroke-dashoffset:-12}}
.inst{animation:glow 3s ease-in-out infinite}
.cw{animation:glow 4s ease-in-out infinite}
@keyframes glow{50%{stroke:#c2410c;stroke-width:2.5}}
@media (prefers-reduced-motion: reduce){.flow-o,.flow-k,.inst,.cw{animation:none}.dot{display:none}}
"""


def head(animate):
    """SVG header; the animated one adds the CSS keyframes."""
    return HEAD.replace("</style>", ANIM_CSS + "</style>", 1) if animate else HEAD


def add_flow_classes(svg):
    """Make arrows flow: tag every solid arrow (line/path with marker-end) with an animated class."""
    def tag(m):
        t = m.group(0)
        if "marker-end" not in t or "marker-start" in t or "stroke-dasharray" in t or "class=" in t:
            return t
        cls = "flow-o" if "#c2410c" in t else "flow-k"
        return "<" + m.group(1) + f' class="{cls}"' + t[1 + len(m.group(1)):]
    return re.sub(r"<(line|path)\b[^>]*>", tag, svg)


def packets(paths):
    """Small dots travelling along the given (path, colour, seconds) routes."""
    out = []
    for d, colour, dur in paths:
        for k in range(2):
            out.append(
                f'<circle class="dot" r="3.5" fill="{colour}"><animateMotion dur="{dur}s" begin="{k * dur / 2:.2f}s" '
                f'repeatCount="indefinite" path="{d}"/></circle>')
    return "".join(out)


def parse_tfvars(path):
    v = {}
    for line in path.read_text().splitlines():
        line = line.split("#")[0].strip()
        m = re.match(r"(\w+)\s*=\s*(.+)$", line)
        if m:
            v[m.group(1)] = m.group(2).strip().strip('"')
    return v


def cidr(vpc, n):
    a, b = vpc.split("/")[0].split(".")[:2]
    return f"{a}.{b}.{n}.0/24"


def build(env, v, compact=False, animate=False):
    vpc = v["vpc_cidr"]
    sa = int(v["standalone_instance_count"])
    amin, amax, adesired = v["asg_min_size"], v["asg_max_size"], v["asg_desired_capacity"]
    dbn = int(v["db_instance_count"])
    dbc = v["db_instance_class"]
    pub = v["db_publicly_accessible"] == "true"
    prot = v["deletion_protection"] == "true"
    nat = v.get("enable_nat_gateway", "false") == "true"
    prefix = f"{v['project']}-{env}"
    it = v["instance_type"]
    ssh = v["ssh_cidr_blocks"].strip("[]").replace('"', "").strip()
    ssh_txt = f"SSH :22 from {ssh}" if ssh else "SSH closed (SSM Session Manager)"
    cf = v.get("enable_cloudfront", "false") == "true"
    waf = cf and v.get("enable_waf", "false") == "true"
    sched = v.get("enable_off_hours_schedule", "false") == "true"
    arch = v.get("cpu_architecture", "x86_64")
    cache = v.get("enable_object_cache", "false") == "true"
    cache_nodes = v.get("cache_node_count", "1")
    flow = v.get("enable_flow_logs", "false") == "true"
    trail = v.get("enable_cloudtrail", "false") == "true"
    gd = v.get("enable_guardduty", "false") == "true"
    prot_txt = "on" if prot else "off"
    o = [] if compact else [head(animate)]
    a = o.append

    a(f'<text x="20" y="22" font-size="15" font-weight="700">{prefix}: multi-AZ WordPress ({v["aws_region"]})</text>')
    if cf:
        a('<rect x="200" y="34" width="140" height="30" rx="4" fill="none" stroke="#1b2330"/><text x="270" y="54" text-anchor="middle">Internet (HTTPS)</text>')
        a('<line x1="340" y1="49" x2="368" y2="49" stroke="#c2410c" stroke-width="2" marker-end="url(#ara)"/>')
        a('<rect x="370" y="30" width="160" height="38" rx="4" fill="#fff" stroke="#c2410c" stroke-width="2"/>'
          '<text x="450" y="46" text-anchor="middle" font-weight="600">CloudFront</text>'
          f'<text class="mono mut" x="450" y="60" text-anchor="middle">{"+ WAF, edge cache" if waf else "edge cache, HTTPS"}</text>')
        a('<line x1="450" y1="68" x2="450" y2="92" stroke="#c2410c" stroke-width="2" marker-end="url(#ara)"/><text class="lbl" x="460" y="84">HTTP + secret header</text>')
    else:
        a('<rect x="380" y="34" width="140" height="30" rx="4" fill="none" stroke="#1b2330"/><text x="450" y="54" text-anchor="middle">Internet (port 80)</text>')
        a('<line x1="450" y1="64" x2="450" y2="92" stroke="#c2410c" stroke-width="2" marker-end="url(#ara)"/><text class="lbl" x="460" y="82">HTTP</text>')
    a(f'<rect x="20" y="92" width="700" height="580" rx="8" fill="#eef2f7" stroke="#8793a6" stroke-width="1.5"/><text class="mono" x="34" y="112">VPC {vpc}</text>')
    a('<rect x="380" y="98" width="140" height="26" rx="4" fill="#fff" stroke="#1b2330"/><text x="450" y="115" text-anchor="middle">Internet gateway</text>')
    a('<line x1="450" y1="124" x2="450" y2="148" stroke="#c2410c" stroke-width="2" marker-end="url(#ara)"/>')
    a(f'<rect x="140" y="148" width="540" height="40" rx="4" fill="#fff" stroke="#c2410c" stroke-width="2"/>'
      f'<text x="410" y="164" text-anchor="middle" font-weight="600">ALB {prefix}-alb</text>'
      f'<text class="mono mut" x="410" y="179" text-anchor="middle">{"listener :80 (CloudFront only)" if cf else "listener :80, :443 with certificate_arn"}, deletion protection {prot_txt}</text>')
    a('<text class="lbl" x="200" y="212" text-anchor="middle">AZ us-east-1a</text><text class="lbl" x="530" y="212" text-anchor="middle">AZ us-east-1b</text>')
    a(f'<rect x="40" y="220" width="320" height="200" rx="6" fill="#e3eefb" stroke="#8793a6"/><text class="mono" x="52" y="238">public-1 {cidr(vpc, 1)}</text>')
    a(f'<rect x="370" y="220" width="330" height="200" rx="6" fill="#e3eefb" stroke="#8793a6"/><text class="mono" x="382" y="238">public-2 {cidr(vpc, 3)}</text>')

    for x in ([110] if sa else []) + [266, 530]:
        a(f'<line x1="{x}" y1="188" x2="{x}" y2="256" stroke="#c2410c" stroke-width="2" marker-end="url(#ara)"/>')
    if sa:
        a('<rect x="60" y="256" width="120" height="58" rx="4" fill="#fff" stroke="#1b2330"/>'
          '<text x="120" y="278" text-anchor="middle" font-weight="600">EC2 standalone</text>'
          f'<text class="mono mut" x="120" y="294" text-anchor="middle">{it}, count {sa}</text>'
          '<text class="mono mut" x="120" y="307" text-anchor="middle">same boot script</text>')
    n_a = (int(adesired) + 1) // 2
    n_b = int(adesired) // 2
    for x, cnt in ((196, n_a), (460, n_b)):
        a(f'<rect class="inst" x="{x}" y="256" width="140" height="58" rx="4" fill="#fff" stroke="#1b2330"/>'
          f'<text x="{x + 70}" y="278" text-anchor="middle" font-weight="600">{cnt} x ASG instance</text>'
          f'<text class="mono mut" x="{x + 70}" y="294" text-anchor="middle">{it}</text>'
          f'<text class="mono mut" x="{x + 70}" y="307" text-anchor="middle">launch template</text>')
    pass
    scale = "can scale out" if int(amax) > int(amin) else "cannot scale out"
    a('<rect x="186" y="244" width="424" height="116" rx="6" fill="none" stroke="#1b2330" stroke-width="1.5" stroke-dasharray="6 4"/>')
    a(f'<text x="398" y="330" text-anchor="middle" font-weight="600">Auto Scaling Group {prefix}-asg</text>')
    a(f'<text class="lbl" x="398" y="343" text-anchor="middle">min {amin} / desired {adesired} / max {amax}, {arch}, CPU + request scaling</text>')
    if sched:
        a('<text class="lbl" x="398" y="356" text-anchor="middle">off hours: 1 instance, 19:00-06:00 UTC and weekends</text>')
    a(f'<text class="lbl" x="52" y="410">{ssh_txt}</text>')

    a(f'<rect x="40" y="440" width="320" height="140" rx="6" fill="#efeaf7" stroke="#8793a6"/><text class="mono" x="52" y="458">private-1 {cidr(vpc, 2)}</text>')
    a(f'<rect x="370" y="440" width="330" height="140" rx="6" fill="#efeaf7" stroke="#8793a6"/><text class="mono" x="382" y="458">private-2 {cidr(vpc, 4)}</text>')
    pos = [110, 450]
    for i in range(dbn):
        x = pos[i % 2]
        role = "writer" if i == 0 else "reader"
        a(f'<rect x="{x}" y="482" width="150" height="58" rx="4" fill="#fff" stroke="#1b2330"/>'
          f'<text x="{x + 75}" y="504" text-anchor="middle" font-weight="600">Aurora instance {i}</text>'
          f'<text class="mono mut" x="{x + 75}" y="520" text-anchor="middle">{dbc} ({role})</text>'
          f'<text class="mono mut" x="{x + 75}" y="533" text-anchor="middle">{prefix}-aurora-{i}</text>')
    if dbn >= 2:
        a('<line x1="260" y1="511" x2="450" y2="511" stroke="#1b2330" marker-start="url(#ar)" marker-end="url(#ar)"/><text class="lbl" x="355" y="504" text-anchor="middle">one cluster</text>')
    a('<rect x="100" y="466" width="510" height="108" rx="6" fill="none" stroke="#1b2330" stroke-width="1.5" stroke-dasharray="6 4"/>')
    a(f'<text class="mono" x="355" y="556" text-anchor="middle" style="font-weight:600">Aurora cluster {prefix}-aurora</text>')
    a(f'<text class="lbl" x="355" y="569" text-anchor="middle">backups {v["db_backup_retention_days"]}d, deletion protection {prot_txt}</text>')
    a('<line x1="266" y1="314" x2="200" y2="482" stroke="#1b2330" stroke-width="1.5" marker-end="url(#ar)"/>')
    tgt = 525 if dbn >= 2 else 220
    a(f'<line x1="530" y1="314" x2="{tgt}" y2="482" stroke="#1b2330" stroke-width="1.5" marker-end="url(#ar)"/>')
    a('<text class="lbl" x="540" y="420">MySQL :3306</text>')
    if pub:
        a(f'<text class="mono warn" x="52" y="600">Aurora publicly accessible: :3306 open to {v["CIDR_BLOCK"]}</text>')
    if nat:
        a('<rect x="60" y="364" width="120" height="36" rx="4" fill="#fff" stroke="#1b2330"/><text x="120" y="386" text-anchor="middle">NAT gateway + EIP</text>')
        a('<line x1="120" y1="440" x2="120" y2="400" stroke="#1b2330" stroke-dasharray="5 4" marker-end="url(#ar)"/>')
    else:
        a('<rect x="60" y="364" width="120" height="36" rx="4" fill="#f3f4f6" stroke="#9ca3af" stroke-dasharray="5 3"/>'
          '<text class="mut" x="120" y="379" text-anchor="middle">NAT gateway + EIP</text>'
          '<text class="mono warn" x="120" y="393" text-anchor="middle">DISABLED</text>')
        a('<line x1="120" y1="440" x2="120" y2="400" stroke="#9ca3af" stroke-dasharray="5 4" marker-end="url(#ar)"/>')
        a('<text class="mono mut" x="52" y="620">enable_nat_gateway = false: NAT is off, private subnets have no internet route</text>')

    # EFS holding the WordPress files, mounted by the ASG instances at boot
    a(f'<rect x="24" y="634" width="692" height="30" rx="4" fill="#fff7ed" stroke="#c2410c" stroke-width="1.5"/>'
      f'<text x="370" y="650" text-anchor="middle" font-weight="600">EFS {prefix}-wordpress-efs</text>'
      '<text class="mono mut" x="370" y="661" text-anchor="middle">WordPress files, NFS :2049, /var/www/html, encrypted, TLS-only, backed up, mount target per AZ</text>')
    a('<path d="M186 324 H30 V634" fill="none" stroke="#c2410c" stroke-width="1.5" marker-end="url(#ara)"/>'
      '<path d="M610 324 H710 V634" fill="none" stroke="#c2410c" stroke-width="1.5" marker-end="url(#ara)"/>')
    # Security controls strip
    alb_sg_txt = "ALB: CloudFront IPs + secret header only; web SG: 80 from ALB" if cf else f'ALB SG: 80/443 from {v["CIDR_BLOCK"]}; web SG: 80 from ALB SG only'
    a('<rect x="20" y="680" width="960" height="62" rx="6" fill="#f3f6fa" stroke="#8793a6"/>')
    a(f'<text class="mono" x="34" y="698">{alb_sg_txt}</text>'
      f'<text class="mono" x="34" y="714">Web egress: 443, 2049, 3306{", 6379 (Redis)" if cache else ""} only</text>'
      f'<text class="mono" x="34" y="730">{ssh_txt}; role {prefix}-web-role</text>'
      '<text class="mono" x="500" y="698">IMDSv2 required, encrypted EBS and EFS (TLS mount)</text>'
      '<text class="mono" x="500" y="714">Aurora private+encrypted; WordPress DB user, not master</text>'
      f'<text class="mono" x="500" y="730">{"WAF + HTTPS at CloudFront; " if waf else ("HTTPS at CloudFront; " if cf else "")}{"flow logs; " if flow else ""}logs TLS-only</text>')
    ret = v["log_retention_days"]
    # S3 log buckets, CloudWatch, account security services
    audit_txt = "audit-logs: CF, flow logs, trail" if trail else ("audit-logs: CloudFront, flow logs" if flow else "audit-logs: CloudFront")
    a('<rect x="750" y="148" width="235" height="84" rx="4" fill="#fff" stroke="#1b2330" stroke-width="1.5"/>'
      '<text x="867" y="168" text-anchor="middle" font-weight="600">S3 log buckets</text>'
      '<text class="mono mut" x="867" y="184" text-anchor="middle">alb-logs: ALB access logs</text>'
      f'<text class="mono mut" x="867" y="198" text-anchor="middle">{audit_txt}</text>'
      f'<text class="mono mut" x="867" y="212" text-anchor="middle">encrypted, expire after {ret} days</text>'
      '<line x1="680" y1="168" x2="748" y2="178" stroke="#1b2330" stroke-width="1.5" marker-end="url(#ar)"/>')
    a('<rect class="cw" x="750" y="246" width="235" height="108" rx="4" fill="#fff" stroke="#1b2330" stroke-width="1.5"/>'
      '<text x="867" y="266" text-anchor="middle" font-weight="600">CloudWatch</text>'
      f'<text class="mono mut" x="867" y="282" text-anchor="middle">dashboard {prefix}-wordpress</text>'
      '<text class="mono mut" x="867" y="296" text-anchor="middle">10 alarms -&gt; SNS: ALB, ASG, DB, EFS</text>'
      '<text class="mono mut" x="867" y="310" text-anchor="middle">agent: memory, disk, Apache logs</text>'
      f'<text class="mono mut" x="867" y="324" text-anchor="middle">Aurora logs, kept {ret} days</text>'
      + ('<text class="mono mut" x="867" y="338" text-anchor="middle">WAF request log</text>' if waf else '')
      + '<line x1="720" y1="300" x2="748" y2="300" stroke="#1b2330" stroke-dasharray="5 4" marker-end="url(#ar)"/>')
    if trail or gd:
        a('<rect x="750" y="364" width="235" height="34" rx="4" fill="#fff" stroke="#1b2330" stroke-width="1.5"/>'
          '<text x="867" y="380" text-anchor="middle" font-weight="600">Account security</text>'
          f'<text class="mono mut" x="867" y="392" text-anchor="middle">{"GuardDuty" if gd else ""}{" + " if gd and trail else ""}{"CloudTrail" if trail else ""}</text>')
    if cache:
        a('<rect x="618" y="482" width="78" height="54" rx="4" fill="#fff" stroke="#1b2330"/>'
          '<text x="657" y="502" text-anchor="middle" font-weight="600">ElastiCache</text>'
          f'<text class="mono mut" x="657" y="516" text-anchor="middle">Redis cache</text>'
          f'<text class="mono mut" x="657" y="529" text-anchor="middle">{cache_nodes} node(s)</text>')
        a('<line x1="590" y1="314" x2="650" y2="482" stroke="#1b2330" stroke-width="1.5" marker-end="url(#ar)"/>')
    if not compact:
        a('<g transform="translate(750 412)"><text class="mono mut">ENVIRONMENT</text>'
          f'<text x="0" y="22">VPC {vpc}</text><text x="0" y="40">Web: {it}</text>'
          f'<text x="0" y="58">ASG: {amin}-{amax} (desired {adesired})</text>'
          f'<text x="0" y="76">Standalone EC2: {sa}</text><text x="0" y="94">Aurora: {dbn} x {dbc}</text>'
          f'<text x="0" y="112">Backups: {v["db_backup_retention_days"]} days</text>'
          f'<text x="0" y="130">Deletion protection: {prot_txt}</text></g>')
        a('<g transform="translate(750 560)"><text class="mono mut">LEGEND</text>'
          '<line x1="0" y1="22" x2="40" y2="22" stroke="#c2410c" stroke-width="2" marker-end="url(#ara)"/><text x="52" y="26">inbound web request</text>'
          '<line x1="0" y1="48" x2="40" y2="48" stroke="#1b2330" stroke-width="1.5" marker-end="url(#ar)"/><text x="52" y="52">database call / logs</text>'
          '<rect x="0" y="66" width="40" height="16" fill="#e3eefb" stroke="#8793a6"/><text x="52" y="79">public subnet</text>'
          '<rect x="0" y="92" width="40" height="16" fill="#efeaf7" stroke="#8793a6"/><text x="52" y="105">private subnet</text></g>')
    if animate:
        o_, k_ = "#c2410c", "#1b2330"
        routes = [("M342 49 H368", o_, 0.8), ("M450 68 V148", o_, 1.2)] if cf else [("M450 64 V148", o_, 1.2)]
        routes += [("M266 188 V256", o_, 1.2), ("M530 188 V256", o_, 1.2)]
        if sa:
            routes += [("M110 188 V256", o_, 1.2)]
        routes += [("M266 314 L200 482", k_, 1.8), (f"M530 314 L{tgt} 482", k_, 1.8), ("M680 168 L748 178", k_, 1.0)]
        if cache:
            routes += [("M590 314 L650 482", k_, 1.6)]
        routes += [("M186 324 H30 V634", o_, 3.0), ("M610 324 H710 V634", o_, 3.0)]
        a(packets(routes))
    if not compact:
        a("</svg>")
    svg = "\n".join(o)
    return add_flow_classes(svg) if animate else svg


for env in ("dev", "test", "prod"):
    v = parse_tfvars(ROOT / "environments" / env / "terraform.tfvars")
    (ROOT / "docs" / f"architecture-{env}.svg").write_bytes(build(env, v).encode("utf-8"))
    (ROOT / "docs" / f"architecture-{env}-animated.svg").write_bytes(build(env, v, animate=True).encode("utf-8"))
    print("wrote", f"docs/architecture-{env}.svg and -animated.svg")


# ---- combined diagram: all environments side by side ----
envs = {e: parse_tfvars(ROOT / "environments" / e / "terraform.tfvars") for e in ("dev", "test", "prod")}
COLW = 1000
rows = [
    ("VPC CIDR", lambda v: v["vpc_cidr"]),
    ("Web instance type", lambda v: v["instance_type"]),
    ("Standalone EC2", lambda v: v["standalone_instance_count"]),
    ("ASG min / desired / max", lambda v: f'{v["asg_min_size"]} / {v["asg_desired_capacity"]} / {v["asg_max_size"]}'),
    ("Aurora", lambda v: f'{v["db_instance_count"]} x {v["db_instance_class"]}'),
    ("DB publicly accessible", lambda v: v["db_publicly_accessible"]),
    ("Backup retention (days)", lambda v: v["db_backup_retention_days"]),
    ("Deletion protection", lambda v: v["deletion_protection"]),
    ("SSH (port 22)", lambda v: "closed (SSM)" if v["ssh_cidr_blocks"].strip("[]").strip() == "" else v["ssh_cidr_blocks"]),
    ("CPU architecture", lambda v: v.get("cpu_architecture", "x86_64") + " (" + v["instance_type"] + ")"),
    ("CloudFront / WAF", lambda v: ("CloudFront" if v.get("enable_cloudfront") == "true" else "none") + (" + WAF" if v.get("enable_waf") == "true" else "")),
    ("Off-hours scale down", lambda v: "yes (1 instance)" if v.get("enable_off_hours_schedule") == "true" else "no"),
    ("Object cache (Redis)", lambda v: ("ElastiCache x" + v.get("cache_node_count", "1")) if v.get("enable_object_cache") == "true" else "none"),
    ("Flow logs / CloudTrail / GuardDuty", lambda v: "flow logs" + (" + CloudTrail" if v.get("enable_cloudtrail") == "true" else "") + (" + GuardDuty" if v.get("enable_guardduty") == "true" else "")),
    ("NAT gateway", lambda v: v.get("enable_nat_gateway", "false")),
    ("EFS (WordPress files)", lambda v: "encrypted, 2 mount targets"),
    ("Log / alarm retention (days)", lambda v: v["log_retention_days"]),
    ("Log bucket force_destroy", lambda v: v["force_destroy_log_bucket"]),
]
def combined(animate=False):
    H = 750 + 40 + 24 * (len(rows) + 1) + 30
    W = COLW * 3
    out = [head(animate).replace('viewBox="0 0 1000 750"', f'viewBox="0 0 {W} {H}"').replace('<rect width="1000" height="750"', f'<rect width="{W}" height="{H}"')]
    out.append(f'<text x="20" y="20" font-size="18" font-weight="700" style="font-size:18px">deham9: multi-AZ WordPress, dev / test / prod</text>')
    out.append('<g transform="translate(1500 8)">'
               '<line x1="0" y1="8" x2="30" y2="8" stroke="#c2410c" stroke-width="2" marker-end="url(#ara)"/><text x="40" y="12">web request</text>'
               '<line x1="150" y1="8" x2="180" y2="8" stroke="#1b2330" stroke-width="1.5" marker-end="url(#ar)"/><text x="190" y="12">database call</text>'
               '<rect x="320" y="0" width="30" height="14" fill="#e3eefb" stroke="#8793a6"/><text x="360" y="12">public subnet</text>'
               '<rect x="470" y="0" width="30" height="14" fill="#efeaf7" stroke="#8793a6"/><text x="510" y="12">private subnet</text></g>')
    for n, (env, v) in enumerate(envs.items()):
        body = build(env, v, compact=True, animate=animate)
        out.append(f'<svg x="{n * COLW}" y="30" width="{COLW}" height="750" viewBox="0 0 {COLW} 750">{body}</svg>')
    ty = 30 + 750 + 20
    out.append(f'<text class="mono mut" x="20" y="{ty}">COMPARISON (same in every env: EFS, private encrypted Aurora, ALB reachable from CloudFront only, ALB access logs to S3, 10 CloudWatch alarms + dashboard + agent logs, Aurora logs to CloudWatch Logs)</text>')
    colx = [260, 260 + COLW, 260 + 2 * COLW]
    for c, env in enumerate(envs):
        out.append(f'<text x="{colx[c]}" y="{ty + 24}" font-weight="700">{env}</text>')
    for r, (label, fn) in enumerate(rows):
        y = ty + 24 * (r + 2)
        if r % 2 == 0:
            out.append(f'<rect x="10" y="{y - 16}" width="{W - 20}" height="24" fill="#f3f6fa"/>')
        out.append(f'<text x="20" y="{y}">{label}</text>')
        for c, v in enumerate(envs.values()):
            out.append(f'<text class="mono" x="{colx[c]}" y="{y}">{fn(v)}</text>')
    out.append("</svg>")
    svg = "\n".join(out)
    return add_flow_classes(svg) if animate else svg


(ROOT / "docs" / "architecture-all-environments.svg").write_bytes(combined().encode("utf-8"))
(ROOT / "docs" / "architecture-all-environments-animated.svg").write_bytes(combined(True).encode("utf-8"))
print("wrote docs/architecture-all-environments.svg and -animated.svg")
