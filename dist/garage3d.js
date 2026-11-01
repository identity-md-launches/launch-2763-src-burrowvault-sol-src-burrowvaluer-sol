// The Hamster Motors garage, a static clay diorama in isometric view. Renders once per resize.
(() => {
  const T = window.THREE, canvas = document.getElementById('garage3d');
  if (!T || !canvas) return;
  let gl;
  try { gl = new T.WebGLRenderer({ canvas, antialias: true, alpha: true, powerPreference: 'low-power' }); } catch { canvas.hidden = true; return; }
  gl.setClearColor(0, 0); gl.outputColorSpace = T.SRGBColorSpace; gl.shadowMap.enabled = true; gl.shadowMap.type = T.PCFSoftShadowMap;
  const scene = new T.Scene(), cam = new T.OrthographicCamera(-5, 5, 3, -3, 0.1, 60);
  cam.position.set(10, 8.2, 10); cam.lookAt(0, 0.9, 0);
  scene.add(new T.HemisphereLight(0xffffff, 0xcabba5, 1.75));
  const key = new T.DirectionalLight(0xfff0dc, 2.3); key.position.set(4, 10, 8); key.castShadow = true; key.shadow.mapSize.set(2048, 2048);
  Object.assign(key.shadow.camera, { left: -8, right: 8, top: 8, bottom: -8, near: 1, far: 30 }); key.shadow.radius = 4; scene.add(key);
  const clay = (c, r = 0.65, m = 0) => new T.MeshStandardMaterial({ color: c, roughness: r, metalness: m });
  /** @param {import('../test/scratch/site-tooling/node_modules/@types/three').Object3D} [parent] */
  const put = (geo, mat, x, y, z, parent = scene) => { const o = new T.Mesh(geo, mat); o.position.set(x, y, z); o.castShadow = o.receiveShadow = true; parent.add(o); return o; };
  const box = (w, h, d, c, x, y, z, parent) => put(new T.BoxGeometry(w, h, d), typeof c === 'number' ? clay(c) : c, x, y, z, parent);
  const cyl = (r, h, c, x, y, z, parent) => put(new T.CylinderGeometry(r, r, h, 36), typeof c === 'number' ? clay(c) : c, x, y, z, parent);

  box(8.4, 0.3, 7.2, 0xd8d4ca, 0, -0.15, 0);                    // slab
  box(8.4, 4, 0.3, 0xe9e2d4, 0, 2, -3.45);                      // back wall
  box(0.3, 4, 7.2, 0xf0d9a8, -4.05, 2, 0);                      // side wall
  box(8.7, 0.34, 0.5, 0xb8791a, 0, 4.15, -3.45);                // eaves
  box(0.5, 0.34, 7.5, 0xb8791a, -4.05, 4.15, 0);
  for (const [z, w] of [[-1.5, 1.5], [0.7, 1.5]]) {             // warm windows on the side wall
    box(0.08, 1.5, w, 0x8c6a3a, -3.88, 2.5, z);
    box(0.1, 1.28, w - 0.22, new T.MeshBasicMaterial({ color: 0xffd98a }), -3.86, 2.5, z);
    box(0.13, 1.28, 0.05, 0x8c6a3a, -3.84, 2.5, z);
  }
  // Sign, drawn on a canvas so the name stays sharp.
  const sign = document.createElement('canvas'); sign.width = 1024; sign.height = 256;
  const x = sign.getContext('2d'); x.fillStyle = '#b8791a'; x.fillRect(0, 0, 1024, 256); x.fillStyle = '#fff6e4'; x.font = '600 112px system-ui, sans-serif'; x.textAlign = 'center'; x.textBaseline = 'middle'; x.fillText('Hamster Motors', 512, 132);
  const tex = new T.CanvasTexture(sign); tex.colorSpace = T.SRGBColorSpace; tex.anisotropy = 8;
  put(new T.BoxGeometry(4.2, 1.05, 0.1), [clay(0xb8791a), clay(0xb8791a), clay(0xb8791a), clay(0xb8791a), new T.MeshStandardMaterial({ map: tex, roughness: 0.6 }), clay(0xb8791a)], 1, 3.05, -3.26);
  // Tool wall
  box(3, 1.2, 0.08, 0x8f9a8c, 1, 1.75, -3.27);
  for (let i = 0; i < 5; i++) box(0.09, 0.7 - i % 2 * 0.2, 0.08, [0xc4c7cb, 0xe0a33e, 0xc4c7cb, 0xc8544a, 0xc4c7cb][i], -0.1 + i * 0.55, 1.75, -3.19);
  // Red tool chest
  const chest = new T.Group(); chest.position.set(-3.1, 0, -2.6); scene.add(chest);
  box(1.1, 1.3, 0.9, 0xc8473f, 0, 0.65, 0, chest);
  for (const y of [0.34, 0.68, 1.02]) box(1.12, 0.05, 0.92, 0x8f2f2a, 0, y, 0, chest);
  // Tyres and the spare hamster wheel
  const tyre = new T.TorusGeometry(0.42, 0.2, 16, 40);
  for (let i = 0; i < 3; i++) { const t = put(tyre, clay(0x2b2a2d, 0.8), 3.2, 0.2 + i * 0.38, -2.6); t.rotation.x = Math.PI / 2; }
  const spare = put(new T.TorusGeometry(0.72, 0.09, 16, 64), clay(0xeec45a), 3.55, 0.82, 1.9); spare.rotation.y = Math.PI / 2.4;
  for (let i = 0; i < 3; i++) { const s = put(new T.CapsuleGeometry(0.03, 1.36, 6, 12), clay(0xeec45a), 3.55, 0.82, 1.9); s.rotation.set(0, Math.PI / 2.4, i * Math.PI / 3, 'YXZ'); }

  // The car
  const car = new T.Group(); car.position.set(0, 0, 0.1); car.rotation.y = 0.36; scene.add(car);
  const paint = clay(0xe58b37, 0.42), glass = new T.MeshStandardMaterial({ color: 0xbfe2ea, roughness: 0.12, transparent: true, opacity: 0.42 });
  box(4.1, 0.62, 1.9, paint, 0, 0.82, 0, car);
  box(4.2, 0.14, 2, 0xfdf6e8, 0, 0.5, 0, car);
  box(2.1, 0.1, 1.76, paint, -0.25, 1.86, 0, car);              // roof on four pillars, so the driver shows
  for (const [px, pz] of [[0.74, 0.82], [0.74, -0.82], [-1.24, 0.82], [-1.24, -0.82]]) box(0.1, 0.76, 0.1, paint, px, 1.46, pz, car);
  box(0.03, 0.72, 1.56, glass, 0.77, 1.46, 0, car);
  for (const z of [-0.8, 0.8]) { box(0.06, 0.2, 0.34, new T.MeshBasicMaterial({ color: 0xfff1b8 }), 2.07, 0.84, z, car); box(0.06, 0.16, 0.34, 0xc8473f, -2.07, 0.84, z, car); }
  for (const [px, pz] of [[1.36, 1], [1.36, -1], [-1.36, 1], [-1.36, -1]]) {
    const w = cyl(0.46, 0.34, 0x2b2a2d, px, 0.46, pz, car); w.rotation.x = Math.PI / 2;
    const h = cyl(0.22, 0.36, 0xeec45a, px, 0.46, pz, car); h.rotation.x = Math.PI / 2;
  }
  // Driver
  const d = new T.Group(); d.position.set(0.05, 1.42, 0.42); d.scale.setScalar(1.06); car.add(d);
  const fur = clay(0xf3d29a, 0.6), ear = clay(0xe7b56f, 0.6), pink = clay(0xf0a9a2, 0.5), eye = new T.MeshStandardMaterial({ color: 0x120c0b, roughness: 0.06 });
  const ball = (r, m, a, b, c, sc = [1, 1, 1]) => { const o = put(new T.SphereGeometry(r, 28, 20), m, a, b, c, d); o.scale.set(sc[0], sc[1], sc[2]); return o; };
  ball(0.36, fur, 0, 0, 0, [1, 0.94, 1]);
  for (const s of [1, -1]) { ball(0.13, ear, -0.08, 0.32, s * 0.2, [0.5, 1.05, 1]); ball(0.09, pink, -0.03, 0.31, s * 0.2, [0.4, 1, 1]); ball(0.04, eye, 0.31, 0.06, s * 0.15); ball(0.1, pink, 0.27, -0.09, s * 0.23, [0.55, 0.7, 1]); }
  ball(0.03, pink, 0.36, -0.03, 0);

  function draw() {
    const w = canvas.clientWidth, h = canvas.clientHeight; if (!w) return;
    gl.setPixelRatio(Math.min(devicePixelRatio, 2)); gl.setSize(w, h, false);
    const v = 4.3, a = w / h; cam.left = -v * a; cam.right = v * a; cam.top = v; cam.bottom = -v; cam.updateProjectionMatrix();
    gl.render(scene, cam);
  }
  new ResizeObserver(draw).observe(canvas); draw();
})();
