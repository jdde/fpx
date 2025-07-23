import json

def generate_badge(coverage_percentage):
    badge_template = f"""
    <svg xmlns="http://www.w3.org/2000/svg" width="98" height="20">
      <linearGradient id="b" x2="0" y2="100%">
        <stop offset="0" stop-color="#bbb" stop-opacity=".1"/>
        <stop offset="1" stop-opacity=".1"/>
      </linearGradient>
      <mask id="a">
        <rect width="98" height="20" rx="3" fill="#fff"/>
      </mask>
      <g mask="url(#a)">
        <path fill="#555" d="M0 0h61v20H0z"/>
        <path fill="#4c1" d="M61 0h37v20H61z"/>
        <path fill="url(#b)" d="M0 0h98v20H0z"/>
      </g>
      <g fill="#fff" text-anchor="middle" font-family="Verdana,Geneva,DejaVu Sans,sans-serif" font-size="110">
        <text x="315" y="150" fill="#010101" fill-opacity=".3" transform="scale(.1)" textLength="510">coverage</text>
        <text x="315" y="140" transform="scale(.1)" textLength="510">coverage</text>
        <text x="785" y="150" fill="#010101" fill-opacity=".3" transform="scale(.1)" textLength="270">{coverage_percentage}%</text>
        <text x="785" y="140" transform="scale(.1)" textLength="270">{coverage_percentage}%</text>
      </g>
    </svg>
    """
    with open("coverage.svg", "w") as f:
        f.write(badge_template)

def main():
    with open("coverage.json") as f:
        data = json.load(f)
        coverage_percentage = data["totals"]["percent_covered_display"]
        generate_badge(coverage_percentage)

if __name__ == "__main__":
    main()