/**
 * TokyoNight Cursor Trail Shader for Ghostty
 *
 * Creates a subtle animated trail effect when the cursor moves, using TokyoNight theme colors.
 * The trail is drawn as a parallelogram connecting the previous and current cursor positions,
 * with a smooth fade-out animation.
 *
 * Features:
 * - Distance-based activation: Only shows trails for navigation movements, not typing
 * - Super fast animation (0.08s) to minimize distraction
 * - Very low opacity colors for maximum subtlety
 *
 * Customization points:
 * - TRAIL_COLOR: Primary trail color (TokyoNight purple)
 * - TRAIL_COLOR_ACCENT: Secondary trail color (TokyoNight moon pink)
 * - DURATION: How long the trail animation lasts in seconds
 * - MIN_DISTANCE_THRESHOLD: Minimum movement distance to trigger trail (typing vs navigation)
 * - Trail thickness: Adjust the 'mod' variable and smoothstep ranges
 *
 * To adjust when trails appear:
 * - Decrease MIN_DISTANCE_THRESHOLD (0.01-0.02) to show trails for smaller movements
 * - Increase MIN_DISTANCE_THRESHOLD (0.03-0.05) to only show trails for larger jumps
 */

// Signed Distance Function for a rectangle
// Returns the distance from point p to the rectangle defined by center xy and half-extents b
float getSdfRectangle(in vec2 p, in vec2 xy, in vec2 b)
{
    vec2 d = abs(p - xy) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Based on Inigo Quilez's 2D distance functions article: https://iquilezles.org/articles/distfunctions2d/
// Optimized by eliminating conditionals and loops to enhance performance and reduce branching

// Calculate distance from point p to line segment a-b, while also tracking inside/outside state
float seg(in vec2 p, in vec2 a, in vec2 b, inout float s, float d) {
    vec2 e = b - a;        // Edge vector
    vec2 w = p - a;        // Vector from segment start to point

    // Project point onto the line segment (clamped to segment bounds)
    vec2 proj = a + e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
    float segd = dot(p - proj, p - proj);  // Squared distance to segment
    d = min(d, segd);      // Update minimum distance

    // Use step functions to determine which side of the edge we're on
    // This is used for inside/outside determination in the parallelogram
    float c0 = step(0.0, p.y - a.y);
    float c1 = 1.0 - step(0.0, p.y - b.y);
    float c2 = 1.0 - step(0.0, e.x * w.y - e.y * w.x);
    float allCond = c0 * c1 * c2;
    float noneCond = (1.0 - c0) * (1.0 - c1) * (1.0 - c2);
    float flip = mix(1.0, -1.0, step(0.5, allCond + noneCond));
    s *= flip;

    return d;
}

// Signed Distance Function for a parallelogram defined by four vertices
// Returns negative values inside the shape, positive outside
float getSdfParallelogram(in vec2 p, in vec2 v0, in vec2 v1, in vec2 v2, in vec2 v3) {
    float s = 1.0;  // Sign multiplier for inside/outside determination
    float d = dot(p - v0, p - v0);  // Initialize with squared distance to first vertex

    // Check distance to each edge of the parallelogram
    d = seg(p, v0, v3, s, d);
    d = seg(p, v1, v0, s, d);
    d = seg(p, v2, v1, s, d);
    d = seg(p, v3, v2, s, d);

    return s * sqrt(d);  // Return signed distance
}

// Normalize coordinates to screen space (-1 to 1)
// isPosition: 1.0 for positions, 0.0 for sizes
vec2 normalize(vec2 value, float isPosition) {
    return (value * 2.0 - (iResolution.xy * isPosition)) / iResolution.y;
}

// Anti-aliasing function using smoothstep for soft edges
float antialising(float distance) {
    return 1. - smoothstep(0., normalize(vec2(2., 2.), 0.).x, distance);
}

// Determine which vertex of the current cursor to use as the parallelogram starting point
// This ensures the trail connects properly regardless of movement direction
float determineStartVertexFactor(vec2 c, vec2 p) {
    // Check movement direction to decide between top-left (0) or top-right (1) vertex
    float condition1 = step(p.x, c.x) * step(c.y, p.y); // Moving right and down
    float condition2 = step(c.x, p.x) * step(p.y, c.y); // Moving left and up

    // Return 1 unless we're in a specific directional case
    return 1.0 - max(condition1, condition2);
}

// Helper function equivalent to (c < p) using step function
float isLess(float c, float p) {
    return 1.0 - step(p, c);
}

// Calculate the center point of a rectangle from its position/size vector
vec2 getRectangleCenter(vec4 rectangle) {
    return vec2(rectangle.x + (rectangle.z / 2.), rectangle.y - (rectangle.w / 2.));
}

// Easing function for smooth trail animation
// Changed from cubic to quadratic for more subtle movement
float ease(float x) {
    return pow(1.0 - x, 2.0);  // Quadratic easing - more subtle than cubic
}

// TokyoNight theme colors with very low opacity for maximum subtlety
const vec4 TRAIL_COLOR = vec4(0.733, 0.608, 0.969, 0.3);        // #bb9af7 - TokyoNight purple with 30% opacity
const vec4 TRAIL_COLOR_ACCENT = vec4(0.988, 0.655, 0.918, 0.15); // #fca7ea - Moon pink with 15% opacity
const float DURATION = 0.08; // Trail duration in seconds - super fast animation

// Distance threshold to differentiate between typing and navigation movements
// Adjust this value to control when trails appear:
// - Lower values (0.01-0.02): Show trails for smaller movements
// - Higher values (0.03-0.05): Only show trails for larger jumps
const float MIN_DISTANCE_THRESHOLD = 0.045; // Normalized distance threshold - increased to prevent trails during typing

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    // Read the current pixel color from the terminal buffer
    #if !defined(WEB)
    fragColor = texture(iChannel0, fragCoord.xy / iResolution.xy);
    #endif

    // Normalize fragment coordinates to screen space (-1 to 1)
    vec2 vu = normalize(fragCoord, 1.);
    vec2 offsetFactor = vec2(-.5, 0.5);  // Offset for cursor positioning

    // Normalize cursor positions and sizes to screen space
    // Current cursor: xy = position (-1 to 1), zw = width/height (0 to 1)
    vec4 currentCursor = vec4(normalize(iCurrentCursor.xy, 1.), normalize(iCurrentCursor.zw, 0.));
    vec4 previousCursor = vec4(normalize(iPreviousCursor.xy, 1.), normalize(iPreviousCursor.zw, 0.));

    // Calculate cursor centers for distance measurements
    vec2 centerCC = getRectangleCenter(currentCursor);
    vec2 centerCP = getRectangleCenter(previousCursor);

    // Determine which vertex to use for the parallelogram trail based on movement direction
    float vertexFactor = determineStartVertexFactor(currentCursor.xy, previousCursor.xy);
    float invertedVertexFactor = 1.0 - vertexFactor;

    // Helper factors for determining movement direction
    float xFactor = isLess(previousCursor.x, currentCursor.x);
    float yFactor = isLess(currentCursor.y, previousCursor.y);

    // Define the four vertices of the parallelogram trail
    // The trail connects the current cursor to the previous cursor position
    vec2 v0 = vec2(currentCursor.x + currentCursor.z * vertexFactor, currentCursor.y - currentCursor.w);
    vec2 v1 = vec2(currentCursor.x + currentCursor.z * xFactor, currentCursor.y - currentCursor.w * yFactor);
    vec2 v2 = vec2(currentCursor.x + currentCursor.z * invertedVertexFactor, currentCursor.y);
    vec2 v3 = centerCP;  // Trail ends at the previous cursor center

    // Calculate signed distance fields for both cursor and trail shapes
    float sdfCurrentCursor = getSdfRectangle(vu, currentCursor.xy - (currentCursor.zw * offsetFactor), currentCursor.zw * 0.5);
    float sdfTrail = getSdfParallelogram(vu, v0, v1, v2, v3);

    // Calculate animation progress (0 to 1 over DURATION seconds)
    float progress = clamp((iTime - iTimeCursorChange) / DURATION, 0.0, 1.0);
    float easedProgress = ease(progress);

    // Distance between cursors determines the trail intensity
    float lineLength = distance(centerCC, centerCP);

    // Calculate distance factor: 0 for movements below threshold, 1 for movements above threshold
    // This eliminates trails during typing (small movements) while preserving them for navigation
    float distanceFactor = step(MIN_DISTANCE_THRESHOLD, lineLength);

    // Trail thickness parameter - reduced to 0.002 for maximum subtlety
    float mod = .002;

    // Create the trail effect with layered colors - much more transparent
    // Start with the accent color (moon pink) for the outer glow
    vec4 trail = mix(TRAIL_COLOR_ACCENT, fragColor, 1. - smoothstep(0., sdfTrail + mod, 0.003));
    // Add the main trail color (purple) with tighter bounds
    trail = mix(TRAIL_COLOR, trail, 1. - smoothstep(0., sdfTrail + mod, 0.002));
    // Ensure the core trail area is very subtly colored
    trail = mix(trail, TRAIL_COLOR, step(sdfTrail + mod, 0.) * 0.5);

    // Add very subtle cursor glow effect - barely visible for default cursor
    trail = mix(TRAIL_COLOR_ACCENT, trail, 1. - smoothstep(0., sdfCurrentCursor + .0005, 0.001));
    trail = mix(TRAIL_COLOR, trail, 1. - smoothstep(0., sdfCurrentCursor + .0005, 0.001) * 0.3);

    // Final blend: fade the trail based on animation progress, distance, and movement threshold
    // The trail only appears for movements above the distance threshold (navigation vs typing)
    // The trail becomes less visible as time progresses and distance increases
    float trailIntensity = smoothstep(0., sdfCurrentCursor, easedProgress * lineLength) * distanceFactor;
    fragColor = mix(trail, fragColor, 1. - trailIntensity);
}