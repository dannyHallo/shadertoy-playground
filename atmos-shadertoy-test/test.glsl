void main() {
    vec2 uv = (gl_FragCoord.xy / iResolution.xy);
    vec4 colRead = texture(iChannel0, uv);
    gl_FragColor = vec4(uv, 0.0, 1.0);
}
