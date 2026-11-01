// Turns a Squeek's on-chain art into a small voxel relief. One shared WebGL context renders every tile,
// so a wallet with 48 NFTs does not need 48 contexts. If anything fails the flat image stays.
(() => {
  const T = window.THREE, GRID = 72, RASTER = GRID * 4, SIZE = 192;
  const REST = { yaw: -0.26, pitch: 0.14 };
  const motionPreference = matchMedia('(prefers-reduced-motion: reduce)');
  let gl, scene, camera;
  const live = new Set();

  function setup() {
    gl = new T.WebGLRenderer({ antialias: true, alpha: true, powerPreference: 'low-power', preserveDrawingBuffer: true });
    gl.setClearColor(0x000000, 0);
    gl.setPixelRatio(1);
    gl.setSize(SIZE * 2, SIZE * 2, false);
    gl.outputColorSpace = T.SRGBColorSpace;
    scene = new T.Scene();
    camera = new T.PerspectiveCamera(24, 1, 0.1, 20);
    camera.position.z = 2;
    scene.add(new T.HemisphereLight(0xffffff, 0x4a4238, 1.5));
    const key = new T.DirectionalLight(0xfff4e2, 2.4);
    key.position.set(-1.2, 1.6, 2);
    scene.add(key);
  }

  // Height comes from how much art surrounds a cell, so the body swells and thin glyphs stay low.
  function voxels(img) {
    const c = document.createElement('canvas'); c.width = c.height = RASTER;
    const x = c.getContext('2d', { willReadFrequently: true });
    x.drawImage(img, 0, 0, RASTER, RASTER);
    const px = x.getImageData(0, 0, RASTER, RASTER).data;   // throws on a tainted canvas: flat image stays
    const cells = new Float32Array(GRID * GRID * 4);
    for (let cy = 0; cy < GRID; cy++) for (let cx = 0; cx < GRID; cx++) {
      let best = 0, r = 0, g = 0, b = 0;
      for (let y = 0; y < 4; y++) for (let k = 0; k < 4; k++) {
        const i = ((cy * 4 + y) * RASTER + cx * 4 + k) * 4, l = Math.max(px[i], px[i + 1], px[i + 2]);
        if (l > best) { best = l; r = px[i]; g = px[i + 1]; b = px[i + 2]; }
      }
      const o = (cy * GRID + cx) * 4;
      cells[o] = r / 255; cells[o + 1] = g / 255; cells[o + 2] = b / 255; cells[o + 3] = best / 255;
    }
    const on = (cx, cy) => cx >= 0 && cy >= 0 && cx < GRID && cy < GRID && cells[(cy * GRID + cx) * 4 + 3] > 0.3;
    const out = [], R = 5;
    for (let cy = 0; cy < GRID; cy++) for (let cx = 0; cx < GRID; cx++) {
      if (!on(cx, cy)) continue;
      let n = 0;
      for (let dy = -R; dy <= R; dy++) for (let dx = -R; dx <= R; dx++) if (on(cx + dx, cy + dy)) n++;
      const o = (cy * GRID + cx) * 4;
      out.push({ cx, cy, h: n / ((2 * R + 1) ** 2), r: cells[o], g: cells[o + 1], b: cells[o + 2] });
    }
    return out;
  }

  function build(cells) {
    const u = 1 / GRID, geo = new T.BoxGeometry(u * 0.92, u * 0.92, 1);
    const mesh = new T.InstancedMesh(geo, new T.MeshStandardMaterial({ roughness: 0.5, metalness: 0.05 }), cells.length);
    const m = new T.Matrix4(), col = new T.Color();
    cells.forEach((c, i) => {
      const depth = 0.05 + c.h * 0.16;
      m.makeScale(1, 1, depth).setPosition((c.cx - GRID / 2) * u, (GRID / 2 - c.cy) * u, depth / 2 - 0.06);
      mesh.setMatrixAt(i, m);
      mesh.setColorAt(i, col.setRGB(c.r, c.g, c.b, T.SRGBColorSpace));
    });
    return mesh;
  }

  function draw(t) {
    t.mesh.rotation.set(t.pitch, t.yaw, 0);
    scene.add(t.mesh);
    gl.render(scene, camera);
    scene.remove(t.mesh);
    t.ctx.clearRect(0, 0, t.canvas.width, t.canvas.height);
    t.ctx.drawImage(gl.domElement, 0, 0, t.canvas.width, t.canvas.height);
  }

  function ease(t) {
    t.yaw += (t.toYaw - t.yaw) * 0.18; t.pitch += (t.toPitch - t.pitch) * 0.18;
    draw(t);
    t.raf = Math.abs(t.toYaw - t.yaw) + Math.abs(t.toPitch - t.pitch) > 0.002 ? requestAnimationFrame(() => ease(t)) : 0;
  }
  const aim = (t, yaw, pitch) => { t.toYaw = yaw; t.toPitch = pitch; if (!t.raf) t.raf = requestAnimationFrame(() => ease(t)); };

  motionPreference.addEventListener('change', () => {
    if (!motionPreference.matches) return;
    for (const t of live) { cancelAnimationFrame(t.raf); t.raf = 0; t.yaw = REST.yaw; t.pitch = REST.pitch; draw(t); }
  });

  window.nft3d = (el, img) => {
    try {
      if (!T) return;
      for (const t of live) if (!t.canvas.isConnected) { cancelAnimationFrame(t.raf); t.mesh.geometry.dispose(); t.mesh.material.dispose(); live.delete(t); }
      if (!gl) setup();
      const cells = voxels(img);
      if (!cells.length) return;
      const canvas = document.createElement('canvas');
      canvas.width = canvas.height = SIZE * 2;
      canvas.setAttribute('role', 'img'); canvas.setAttribute('aria-label', img.alt);
      const t = { canvas, ctx: canvas.getContext('2d'), mesh: build(cells), yaw: REST.yaw, pitch: REST.pitch, toYaw: REST.yaw, toPitch: REST.pitch, raf: 0 };
      live.add(t);
      el.replaceChildren(canvas);
      draw(t);

      el.addEventListener('pointermove', event => {
        if (motionPreference.matches) return;
        const e = /** @type {PointerEvent} */ (event);
        const b = el.getBoundingClientRect();
        aim(t, ((e.clientX - b.left) / b.width - 0.5) * 1.3, ((e.clientY - b.top) / b.height - 0.5) * 0.9);
      });
      el.addEventListener('pointerleave', () => { if (!motionPreference.matches) aim(t, REST.yaw, REST.pitch); });
    } catch { /* flat image remains */ }
  };
})();
