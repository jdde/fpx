import re
import sys
import os

def extract_coverage_from_lcov(lcov_file_path):
    """Extract coverage percentage from lcov.info file."""
    try:
        with open(lcov_file_path, 'r') as f:
            content = f.read()
        
        # Find all LH (lines hit) and LF (lines found) entries
        lines_hit = 0
        lines_found = 0
        
        # Extract LH (lines hit) values
        lh_matches = re.findall(r'^LH:(\d+)', content, re.MULTILINE)
        for match in lh_matches:
            lines_hit += int(match)
        
        # Extract LF (lines found) values  
        lf_matches = re.findall(r'^LF:(\d+)', content, re.MULTILINE)
        for match in lf_matches:
            lines_found += int(match)
        
        if lines_found == 0:
            return 0.0
        
        coverage_percentage = (lines_hit / lines_found) * 100
        return round(coverage_percentage, 1)
        
    except FileNotFoundError:
        print(f"Error: Could not find lcov file at {lcov_file_path}")
        return 0.0
    except Exception as e:
        print(f"Error reading lcov file: {e}")
        return 0.0

def get_badge_color(coverage_percentage):
    """Get appropriate color for the coverage badge."""
    if coverage_percentage >= 90:
        return "#4c1"  # bright green
    elif coverage_percentage >= 80:
        return "#97CA00"  # green
    elif coverage_percentage >= 70:
        return "#a4a61d"  # yellow-green
    elif coverage_percentage >= 60:
        return "#dfb317"  # yellow
    elif coverage_percentage >= 50:
        return "#fe7d37"  # orange
    else:
        return "#e05d44"  # red

def generate_badge(coverage_percentage):
    """Generate SVG badge with coverage percentage."""
    color = get_badge_color(coverage_percentage)
    
    badge_template = f"""<svg xmlns="http://www.w3.org/2000/svg" width="98" height="20">
  <linearGradient id="b" x2="0" y2="100%">
    <stop offset="0" stop-color="#bbb" stop-opacity=".1"/>
    <stop offset="1" stop-opacity=".1"/>
  </linearGradient>
  <mask id="a">
    <rect width="98" height="20" rx="3" fill="#fff"/>
  </mask>
  <g mask="url(#a)">
    <path fill="#555" d="M0 0h61v20H0z"/>
    <path fill="{color}" d="M61 0h37v20H61z"/>
    <path fill="url(#b)" d="M0 0h98v20H0z"/>
  </g>
  <g fill="#fff" text-anchor="middle" font-family="Verdana,Geneva,DejaVu Sans,sans-serif" font-size="110">
    <text x="315" y="150" fill="#010101" fill-opacity=".3" transform="scale(.1)" textLength="510">coverage</text>
    <text x="315" y="140" transform="scale(.1)" textLength="510">coverage</text>
    <text x="785" y="150" fill="#010101" fill-opacity=".3" transform="scale(.1)" textLength="270">{coverage_percentage}%</text>
    <text x="785" y="140" transform="scale(.1)" textLength="270">{coverage_percentage}%</text>
  </g>
</svg>"""
    
    with open("coverage_badge.svg", "w") as f:
        f.write(badge_template)
    
    print(f"Generated coverage badge with {coverage_percentage}% coverage")

def main():
    # Default lcov file path
    lcov_file_path = "coverage/lcov.info"
    
    # Allow custom lcov file path as command line argument
    if len(sys.argv) > 1:
        lcov_file_path = sys.argv[1]
    
    # Check if lcov file exists
    if not os.path.exists(lcov_file_path):
        print(f"Error: lcov file not found at {lcov_file_path}")
        sys.exit(1)
    
    # Extract coverage percentage
    coverage_percentage = extract_coverage_from_lcov(lcov_file_path)
    
    if coverage_percentage is None:
        print("Error: Could not extract coverage percentage")
        sys.exit(1)
    
    print(f"Coverage: {coverage_percentage}%")
    
    # Generate badge
    generate_badge(coverage_percentage)

if __name__ == "__main__":
    main()