uniform sampler2D frontTex, matteTex, selectiveTex;
uniform float threshold, cyan, magenta, yellow, adsk_result_w, adsk_result_h;
uniform int method, workingSpace;
uniform bool invert;

// calc hyperbolic tangent
float tanh( float val) {
    float f = exp(2.0*val);
    return (f-1.0) / (f+1.0);
}

// calc inverse hyperbolic tangent
float atanh( float val) {
    return log((1.0+val)/(1.0-val))/2.0;
}

// Convert ACEScg to ACEScct
float lin_to_ACEScct(float val)
{
    if (val <= 0.0078125)
    {
        return 10.5402377416545 * val + 0.0729055341958355;
    }
    else
    {
        return (log2(val) + 9.72) / 17.52;
    }   
}

// Convert ACEScct to ACEScg
float ACEScct_to_lin(float val)
{
    if (val > 0.155251141552511)
    {
        return pow( 2.0, val*17.52 - 9.72);
    }
    else
    {
        return (val - 0.0729055341958355) / 10.5402377416545;
    }
}

void main() {
    vec2 coords = gl_FragCoord.xy / vec2( adsk_result_w, adsk_result_h );
    vec3 src = texture2D(frontTex, coords).rgb;
    float alpha = texture2D(matteTex, coords).g;
    float select = texture2D(selectiveTex, coords).g;
    vec3 dst;

    // thr is the complement of threshold. 
    // that is: the percentage of the core gamut to protect
    float thr = 1.0 - threshold;

    // bias limits by color component
    // range is limited to 0.00001 > lim < 1/thr
    // cyan = 0: no compression
    // cyan = 1: "normal" compression with limit at 1.0
    // 1 > cyan < 1/thr : compress more than edge of gamut. max = hard clip (e.g., thr=0.8, max = 1.25)
    vec3 lim;
    lim.x = 1.0/max(0.00001, min(1.0/thr, cyan));
    lim.y = 1.0/max(0.00001, min(1.0/thr, magenta));
    lim.z = 1.0/max(0.00001, min(1.0/thr, yellow));

    float r = src.x;
    float g = src.y;
    float b = src.z;

    if (workingSpace == 1) {
        r = ACEScct_to_lin(r);
        g = ACEScct_to_lin(g);
        b = ACEScct_to_lin(b);
    }

    // achromatic axis 
    float ach = max(r, max(g, b));

    // distance from the achromatic axis for each color component
    float d_r, d_g, d_b;
    d_r = ach == 0.0 ? 0.0 : abs(float(r-ach)) / ach;
    d_g = ach == 0.0 ? 0.0 : abs(float(g-ach)) / ach;
    d_b = ach == 0.0 ? 0.0 : abs(float(b-ach)) / ach;

    // compress distance for each color component
    // method 0 : tanh - hyperbolic tangent compression method suggested by Thomas Mansencal https://community.acescentral.com/t/simplistic-gamut-mapping-approaches-in-nuke/2679/2
    // method 1 : exp - natural exponent compression method
    // method 2 : simple - simple Reinhard type compression suggested by Nick Shaw https://community.acescentral.com/t/simplistic-gamut-mapping-approaches-in-nuke/2679/3
    // example plots for each method: https://www.desmos.com/calculator/x69iyptspq
    float cd_r, cd_g, cd_b;
    if (method == 0) {
      if (!invert) {
        cd_r = d_r > thr ? thr + (lim.x - thr) * tanh( ( (d_r - thr)/( lim.x-thr))) : d_r;
        cd_g = d_g > thr ? thr + (lim.y - thr) * tanh( ( (d_g - thr)/( lim.y-thr))) : d_g;
        cd_b = d_b > thr ? thr + (lim.z - thr) * tanh( ( (d_b - thr)/( lim.z-thr))) : d_b;
      } else {
          cd_r = d_r > thr ? thr + (lim.x - thr) * atanh( d_r/( lim.x - thr) - thr/( lim.x - thr)) : d_r;
          cd_g = d_g > thr ? thr + (lim.y - thr) * atanh( d_g/( lim.y - thr) - thr/( lim.y - thr)) : d_g;
          cd_b = d_b > thr ? thr + (lim.z - thr) * atanh( d_b/( lim.z - thr) - thr/( lim.z - thr)) : d_b;
      }
    } else if (method == 1) {
      if (!invert) {
        cd_r = d_r > thr ? lim.x-(lim.x-thr)*exp(-(((d_r-thr)*((1.0*lim.x)/(lim.x-thr))/lim.x))) : d_r;
        cd_g = d_g > thr ? lim.y-(lim.y-thr)*exp(-(((d_g-thr)*((1.0*lim.y)/(lim.y-thr))/lim.y))) : d_g;
        cd_b = d_b > thr ? lim.z-(lim.z-thr)*exp(-(((d_b-thr)*((1.0*lim.z)/(lim.z-thr))/lim.z))) : d_b;
      } else {
        cd_r = d_r > thr ? -log( (d_r-lim.x)/(thr-lim.x))*(-thr+lim.x)/1.0+thr : d_r;
        cd_g = d_g > thr ? -log( (d_g-lim.y)/(thr-lim.y))*(-thr+lim.y)/1.0+thr : d_g;
        cd_b = d_b > thr ? -log( (d_b-lim.z)/(thr-lim.z))*(-thr+lim.z)/1.0+thr : d_b;
      }
    } else if (method == 2) {
      if (!invert) {
        cd_r = d_r > thr ? thr+(-1.0/((d_r-thr)/(lim.x-thr)+1.0)+1.0)*(lim.x-thr) : d_r;
        cd_g = d_g > thr ? thr+(-1.0/((d_g-thr)/(lim.y-thr)+1.0)+1.0)*(lim.y-thr) : d_g;
        cd_b = d_b > thr ? thr+(-1.0/((d_b-thr)/(lim.z-thr)+1.0)+1.0)*(lim.z-thr) : d_b;
      } else {
        cd_r = d_r > thr ? (pow(thr, 2.0) - thr*d_r + (lim.x-thr)*d_r) / (thr + (lim.x-thr) - d_r) : d_r;
        cd_g = d_g > thr ? (pow(thr, 2.0) - thr*d_g + (lim.y-thr)*d_g) / (thr + (lim.y-thr) - d_g) : d_g;
        cd_b = d_b > thr ? (pow(thr, 2.0) - thr*d_b + (lim.z-thr)*d_b) / (thr + (lim.z-thr) - d_b) : d_b;
      }
    }

    // scale each color component relative to achromatic axis by gamut compression factor
    dst.x = ach-cd_r*ach;
    dst.y = ach-cd_g*ach;
    dst.z = ach-cd_b*ach;

    // write to output
    if (workingSpace == 1) {
        dst.x = lin_to_ACEScct(dst.x);
        dst.y = lin_to_ACEScct(dst.y);
        dst.z = lin_to_ACEScct(dst.z);
    }

    dst = mix(src, dst, select);

	gl_FragColor = vec4(dst, alpha);
}
