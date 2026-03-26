"""
Generate Skyplots view given objects NORAD and UTC time. 
"""
import matplotlib.pyplot as plt
import numpy as np
import requests
from skyfield.api import EarthSatellite, load, wgs84

def extract_tle(data):
    """Recursively searches a JSON structure to find standard TLE lines."""
    lines = []
    if isinstance(data, dict):
        for v in data.values():
            lines.extend(extract_tle(v))
    elif isinstance(data, list):
        for item in data:
            lines.extend(extract_tle(item))
    elif isinstance(data, str):
        data_stripped = data.strip()
        # Look for standard 69-character TLE lines starting with '1 ' or '2 '
        if (data_stripped.startswith('1 ') or data_stripped.startswith('2 ')) and len(data_stripped) >= 68:
            lines.append(data_stripped)
    return lines

def get_historical_tle(norad_id, jd_date):
    """Fetches the nearest TLE from the IAU SatChecker API for a given date"""
    url = 'https://satchecker.cps.iau.org/tools/get-nearest-tle/'
    params = {
        'id': str(norad_id),
        'id_type': 'catalog',
        'epoch': str(jd_date)
    }
    
    print(f"  Fetching TLE for ID {norad_id}...")
    response = requests.get(url, params=params)
    response.raise_for_status() 
    
    tle_lines = extract_tle(response.json())
    line1 = next((line for line in tle_lines if line.startswith('1 ')), None)
    line2 = next((line for line in tle_lines if line.startswith('2 ')), None)
    
    if not line1 or not line2:
        raise ValueError(f"Could not parse TLE lines from API response.")
        
    return line1, line2

def plot_multiple_satellites():
    satellites_to_track = {
        28190: "PRN 19",
        28874: "PRN 17",
        29486: "PRN 31",
        40294: "PRN 03",
        22877: "PRN 04",
        40105: "PRN 09",
        39741: "PRN 06",
        48859: "PRN 11",
        40534: "PRN 26",
        62339: "PRN 01",
        32711: "PRN 07", 
        #64202: "PRN 21"
    }

    ts = load.timescale()
    t = ts.utc(2026, 3, 18, 21, 00, 0) 

    observer = wgs84.latlon(45.030447, 7.723046)

    fig = plt.figure(figsize=(8, 8)) 
    ax = fig.add_subplot(111, polar=True)

    ax.set_theta_zero_location('N') # North at the top
    ax.set_theta_direction(-1)      # Clockwise angles (East is right)
    ax.set_rlim(bottom=90, top=0)   # Zenith (90) at center, Horizon (0) at edge
    ax.set_yticks(np.arange(0, 91, 15))
    ax.set_yticklabels(map(str, np.arange(0, 91, 15)))
    
    at_least_one_visible = False

    print(f"Calculating positions for {t.utc_strftime('%Y-%m-%d %H:%M:%S UTC')}...")

    # plot each sat
    for norad_id, name in satellites_to_track.items():
        print(f"\nProcessing {name}...")
        try:
            line1, line2 = get_historical_tle(norad_id, t.tt)
        except Exception as e:
            print(f"  Failed to fetch TLE: {e}")
            continue

        satellite = EarthSatellite(line1, line2, name, ts)
        difference = satellite - observer
        topocentric = difference.at(t)
        alt, az, distance = topocentric.altaz()

        if alt.degrees < 0:
            print(f"  Status: Below horizon ({alt.degrees:.1f}°)")
            continue

        print(f"  Status: Visible! Az: {az.degrees:.1f}°, El: {alt.degrees:.1f}°")
        
        # Plot this specific satellite
        azimuth_rad = np.radians(az.degrees)
        ax.plot(azimuth_rad, alt.degrees, 'o', markersize=8, label=f"{name}")
        
        # Annotate the point with PRN, Azimuth, and Elevation
        label_text = f"{name}\nAz: {az.degrees:.1f}°\nEl: {alt.degrees:.1f}°"
        ax.annotate(label_text,
                    xy=(azimuth_rad, alt.degrees),
                    xytext=(8, 8), # Offset text slightly from the dot
                    textcoords='offset points',
                    fontsize=8,
                    bbox=dict(boxstyle="round,pad=0.3", fc="white", ec="gray", alpha=0.8))
        
        at_least_one_visible = True

    ax.set_title(f"Multi-Satellite Sky Plot\n{t.utc_strftime('%Y-%m-%d %H:%M:%S UTC')}\nTurin, Italy", va='bottom', pad=20)
    
    if at_least_one_visible:
        ax.legend(loc='upper right', bbox_to_anchor=(1.35, 1.1))
    else:
        ax.text(0.5, 0.5, 'All selected satellites\n are below the horizon.', 
                horizontalalignment='center', verticalalignment='center', 
                transform=ax.transAxes, color='red', weight='bold')

    filename = 'annotated_skyplot.png'
    plt.savefig(filename, bbox_inches='tight', dpi=150)
    print(f"\nDone! Plot saved locally as '{filename}'.")

    plt.show()

if __name__ == "__main__":
    plot_multiple_satellites()