// The Squeekchain hamster wheel, rendered with three.js.
// It turns at the live rpm from the hardware feed (app.js dispatches "wheel") and rests when the wheel is idle.
const T = window.THREE;
const canvas = /** @type {HTMLCanvasElement} */ (document.getElementById('wheel3d'));
const stage = document.getElementById('stage');
const cap = document.getElementById('wheelCap');
const motionPreference = matchMedia('(prefers-reduced-motion: reduce)');
let reduced = motionPreference.matches;

let renderer;
try {
  if (!T) throw new Error('three missing');
  renderer = new T.WebGLRenderer({ canvas, antialias: true, alpha: true, powerPreference: 'low-power' });
} catch { stage.hidden = true; document.querySelector('.hero').classList.add('no-gl'); }

if (renderer) {
  renderer.setClearColor(0x000000, 0);
  renderer.outputColorSpace = T.SRGBColorSpace;
  renderer.toneMapping = T.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.05;
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = T.PCFSoftShadowMap;

  const scene = new T.Scene();
  const camera = new T.PerspectiveCamera(28, 1, 0.1, 50);

  // Reflections for the metal come from a small studio built in code: two softboxes and a warm bounce.
  const studio = new T.Scene();
  studio.background = new T.Color(0x1c1a18);
  const box = (w, h, x, y, z, color, power) => {
    const m = new T.Mesh(new T.PlaneGeometry(w, h), new T.MeshBasicMaterial({ color: new T.Color(color).multiplyScalar(power), side: T.DoubleSide }));
    m.position.set(x, y, z); m.lookAt(0, 0, 0); studio.add(m);
  };
  box(6, 4, -5, 5, 4, 0xffffff, 6);
  box(2, 6, 6, 2, 2, 0xfff1d6, 3);
  box(8, 2, 0, -3, -5, 0xd9a441, 1.2);
  const pmrem = new T.PMREMGenerator(renderer);
  scene.environment = pmrem.fromScene(studio, 0.04).texture;
  pmrem.dispose();

  const key = new T.DirectionalLight(0xfff4e2, 2.2);
  key.position.set(-2, 6.5, 2.2);
  key.castShadow = true;
  key.shadow.mapSize.set(1024, 1024);
  Object.assign(key.shadow.camera, { left: -4, right: 4, top: 4, bottom: -4, near: 1, far: 16 });
  key.shadow.radius = 5; key.shadow.bias = -0.0004;
  scene.add(key);
  scene.add(new T.HemisphereLight(0xdfe6ee, 0x3a2f24, 0.35));

  // A clay diorama. Squeektoshi stands in front of a toy wheel on a sage plinth, seeds in a bowl.
  const clay = (color, roughness = 0.62) => new T.MeshStandardMaterial({ color, roughness, metalness: 0 });
  const yellow = clay(0xeec45a), yellowDeep = clay(0xdcab3f), sage = clay(0xb7cdb0, 0.8), seedMat = clay(0xa9805a, 0.55);
  /** @param {import('../test/scratch/site-tooling/node_modules/@types/three').Object3D} [parent] */
  const add = (geo, mat, x, y, z, parent = scene) => { const m = new T.Mesh(geo, mat); m.position.set(x, y, z); m.castShadow = true; m.receiveShadow = true; parent.add(m); return m; };

  const R = 1.08;
  const wheel = new T.Group();
  for (const z of [-0.2, 0.2]) add(new T.TorusGeometry(R, 0.075, 24, 120), yellow, 0, 0, z, wheel);
  const tread = add(new T.CylinderGeometry(R, R, 0.4, 96, 1, true), yellowDeep, 0, 0, 0, wheel);
  tread.rotation.x = Math.PI / 2; tread.material.side = T.DoubleSide;
  for (let i = 0; i < 4; i++) {
    const s = add(new T.CapsuleGeometry(0.052, 2 * R - 0.1, 8, 20), yellow, 0, 0, -0.2, wheel);
    s.rotation.z = (i / 4) * Math.PI + Math.PI / 8;
  }
  const hub = add(new T.CylinderGeometry(0.17, 0.17, 0.16, 40), yellowDeep, 0, 0, -0.22, wheel);
  hub.rotation.x = Math.PI / 2;
  scene.add(wheel);

  const plinth = add(new T.CylinderGeometry(2.25, 2.3, 0.1, 96), sage, 0.1, -1.3, 0.25);
  const deck = add(new T.CylinderGeometry(1.62, 1.68, 0.16, 96), yellowDeep, 0, -1.17, 0.12);
  deck.scale.z = 0.72;
  for (const x of [-0.82, 0.82]) { const leg = add(new T.CapsuleGeometry(0.1, 0.92, 8, 20), yellow, x * 0.55, -0.66, -0.42); leg.rotation.z = x > 0 ? -0.5 : 0.5; }
  add(new T.CylinderGeometry(0.06, 0.06, 0.4, 20), yellowDeep, 0, 0, -0.42).rotation.x = Math.PI / 2;
  const bowlShape = [[0, 0], [0.26, 0], [0.34, 0.03], [0.4, 0.2], [0.37, 0.21], [0.31, 0.07], [0, 0.07]].map(p => new T.Vector2(...p));
  const bowl = add(new T.LatheGeometry(bowlShape, 48), yellow, 1.2, -1.25, 0.95); bowl.material.side = T.DoubleSide;
  const seed = new T.SphereGeometry(0.05, 14, 10);
  const scatter = [[1.12, -1.09, 0.92], [1.22, -1.08, 1.02], [1.3, -1.09, 0.9], [1.2, -1.07, 0.86], [1.08, -1.09, 1.02], [1.3, -1.09, 1.03], [1.2, -1.1, 0.95],
    [0.5, -1.22, 1.5], [0.84, -1.22, 1.62], [1.58, -1.22, 1.32], [-0.5, -1.22, 1.58], [-1.3, -1.22, 1.22], [1.74, -1.22, 0.62]];
  scatter.forEach(([x, y, z], i) => { const m = add(seed, seedMat, x, y, z); m.scale.set(1.3, 0.62, 0.8); m.rotation.set(i, i * 2, 0); });

  // Squeektoshi is one surface: shapes blend with a smooth union and a sphere is projected onto it.
  const SHAPES = [[0, -.08, 0, .47, .5, .44], [0, -.3, .04, .5, .3, .44], [0, .46, 0, .4, .35, .38], [.28, .34, .15, .2, .18, .17], [-.28, .34, .15, .2, .18, .17], [0, .36, .32, .12, .09, .09]];
  const ell = (p, s) => { const q = Math.hypot((p.x - s[0]) / s[3], (p.y - s[1]) / s[4], (p.z - s[2]) / s[5]); return (q - 1) * Math.min(s[3], s[4], s[5]); };
  const smin = (a, b, k) => { const h = Math.max(k - Math.abs(a - b), 0) / k; return Math.min(a, b) - h * h * k * 0.25; };
  const sdf = p => SHAPES.reduce((d, s) => smin(d, ell(p, s), 0.12), 1e3);
  const cast = (o, d) => { let lo = 0, hi = 1.5; const p = new T.Vector3(); for (let i = 0; i < 26; i++) { const t = (lo + hi) / 2; p.copy(o).addScaledVector(d, t); sdf(p) < 0 ? lo = t : hi = t; } return p.clone(); };
  const geo = new T.SphereGeometry(1, 128, 96), P = geo.attributes.position, O = new T.Vector3(0, 0.08, 0), Cc = new Float32Array(P.count * 3);
  const tan = new T.Color(0xe7b56f), honey = new T.Color(0xf3d29a), cream = new T.Color(0xfdf6e8), blush = new T.Color(0xf6a9a2), col = new T.Color(), dir = new T.Vector3();
  const ss = T.MathUtils.smoothstep;
  for (let i = 0; i < P.count; i++) {
    dir.fromBufferAttribute(P, i).normalize();
    const p = cast(O, dir); P.setXYZ(i, p.x, p.y, p.z);
    col.copy(honey).lerp(tan, ss(p.y, 0.1, 0.7) * 0.6 + ss(-p.z, 0, 0.4) * 0.5);
    const belly = (1 - ss(Math.hypot(p.x / 0.36, (p.y + 0.16) / 0.5), 0.72, 1.05)) * ss(p.z, 0, 0.2);
    const muzzle = (1 - ss(Math.hypot(p.x / 0.19, (p.y - 0.33) / 0.15), 0.7, 1.1)) * ss(p.z, 0.1, 0.25);
    col.lerp(cream, Math.max(belly, muzzle));
    const c = Math.exp(-(((Math.abs(p.x) - 0.31) / 0.11) ** 2 + ((p.y - 0.37) / 0.08) ** 2)) * ss(p.z, 0, 0.15);
    col.lerp(blush, c * 0.8);
    Cc.set([col.r, col.g, col.b], i * 3);
  }
  geo.setAttribute('color', new T.BufferAttribute(Cc, 3)); geo.computeVertexNormals();
  const fur = new T.MeshStandardMaterial({ vertexColors: true, roughness: 0.66 });
  const pink = clay(0xf0a9a2, 0.5), tanMat = clay(0xe7b56f, 0.66), honeyMat = clay(0xf3d29a, 0.66);
  const dark = new T.MeshStandardMaterial({ color: 0x120c0b, roughness: 0.06 });
  const shine = new T.MeshBasicMaterial({ color: 0xffffff }), line = clay(0x4a2f25, 0.5);
  const hamster = new T.Group();
  const coat = new T.Mesh(geo, fur); coat.castShadow = true; hamster.add(coat);
  const ball = (r, mat, pos, sc = [1, 1, 1], parent = hamster) => { const m = new T.Mesh(new T.SphereGeometry(r, 32, 24), mat); m.position.copy(pos); m.scale.set(sc[0], sc[1], sc[2]); m.castShadow = true; parent.add(m); return m; };
  const V = (x, y, z) => new T.Vector3(x, y, z);
  const headC = V(0, 0.46, 0), onHead = (x, y, z) => cast(headC, V(x, y, z).normalize());
  const openEyes = [], shutEyes = [];
  for (const s of [1, -1]) {
    const e = onHead(s * 0.48, 0.2, 0.86);
    openEyes.push(ball(0.062, dark, e, [1, 1.12, 0.62]));
    openEyes.push(ball(0.019, shine, e.clone().add(V(0.018, 0.03, 0.035))));
    openEyes.push(ball(0.009, shine, e.clone().add(V(-0.02, -0.022, 0.036))));
    const shut = new T.Mesh(new T.TorusGeometry(0.05, 0.009, 10, 24, Math.PI), line);
    shut.position.copy(e).add(V(0, -0.012, 0.012)); shut.rotation.z = Math.PI; hamster.add(shut); shutEyes.push(shut);
    const earP = V(s * 0.3, 0.8, -0.03);
    const ear = ball(0.17, tanMat, earP, [1, 1.1, 0.36]); ear.rotation.z = -s * 0.32;
    const inner = ball(0.122, pink, earP.clone().add(V(-s * 0.004, -0.01, 0.045)), [1, 1.08, 0.3]); inner.rotation.z = -s * 0.32;
    for (const [dy, dx] of [[.05, .34], [0, .37], [-.05, .34]]) {
      const a = V(s * 0.1, 0.34, 0.42);
      hamster.add(new T.Line(new T.BufferGeometry().setFromPoints([a, a.clone().add(V(s * dx, dy, -0.08))]), new T.LineBasicMaterial({ color: 0x5b4636 })));
    }
  }
  ball(0.026, pink, cast(V(0, 0.36, 0.3), V(0, 0.2, 1).normalize()), [1.25, 0.8, 0.8]);
  for (const s of [1, -1]) { const m = new T.Mesh(new T.TorusGeometry(0.03, 0.007, 8, 18, Math.PI), line); m.position.copy(onHead(s * 0.08, -0.2, 1)).add(V(0, 0.002, 0.012)); m.rotation.z = Math.PI; hamster.add(m); }
  const paw = (s, y, z) => { const g = new T.Group(); g.position.set(s * 0.22, y, z); hamster.add(g); ball(0.085, honeyMat, V(0, -0.02, 0), [0.85, 1.1, 0.8], g); ball(0.05, pink, V(0, -0.075, 0.03), [1.05, 0.72, 0.8], g); return g; };
  const arms = [paw(1, 0.04, 0.43), paw(-1, 0.04, 0.43)];
  const feet = [1, -1].map(s => ball(0.09, pink, V(s * 0.27, -0.55, 0.3), [1.1, 0.42, 1.45]));
  hamster.scale.setScalar(0.92);
  hamster.rotation.y = -0.1;
  scene.add(hamster);
  const pose = (phase, on) => {
    arms.forEach((g, i) => { g.rotation.x = on ? Math.sin(phase + i * Math.PI) * 0.9 : 0.2; });
    feet.forEach((f, i) => { f.position.y = -0.55 + (on ? Math.max(0, Math.sin(phase + i * Math.PI)) * 0.08 : 0); });
    hamster.position.set(-0.08, -0.55 + (on ? Math.abs(Math.sin(phase)) * 0.04 : -0.035), 0.62);
    hamster.scale.y = on ? 0.92 : 0.86;
    hamster.rotation.z = on ? Math.sin(phase) * 0.03 : 0.05;
    openEyes.forEach(e => { e.visible = on; }); shutEyes.forEach(e => { e.visible = !on; });
  };
  pose(0, false);

  const fill = new T.DirectionalLight(0xfff2e0, 1.15); fill.position.set(0.6, -0.4, 6); scene.add(fill);   // lifts the belly
  const floor = new T.Mesh(new T.PlaneGeometry(14, 14), new T.ShadowMaterial({ opacity: 0.2 }));
  floor.rotation.x = -Math.PI / 2; floor.position.y = -1.36; floor.receiveShadow = true; scene.add(floor);
  wheel.rotation.z = 0.2;
  scene.rotation.y = -0.2;

  const size = () => {
    const w = stage.clientWidth, h = stage.clientHeight; if (!w || !h) return;
    renderer.setPixelRatio(Math.min(devicePixelRatio || 1, 2));
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    const d = 6.4 * Math.max(1, 1.25 / camera.aspect);
    camera.position.set(0.3, 1.1, d);
    camera.lookAt(0.05, -0.32, 0);
    camera.updateProjectionMatrix();
    draw();
  };
  const draw = () => renderer.render(scene, camera);

  // Angular velocity eases toward the live rpm so the wheel spins up and coasts down like a real one.
  let target = 0, vel = 0, raf = 0, last = 0, visible = true, stride = 0;
  const tick = now => {
    const elapsed = Math.max(0, (now - last) / 1000 || 0), dt = Math.min(0.05, elapsed); last = now;
    vel += (target - vel) * (1 - Math.exp(-elapsed * 2.2));
    if (target === 0 && Math.abs(vel) < 0.002) vel = 0;
    wheel.rotation.z -= vel * dt;
    stride += vel * dt * 3.2; pose(stride, vel > 0.02);
    draw();
    raf = vel !== 0 || target !== 0 ? requestAnimationFrame(tick) : 0;
  };
  const run = () => { if (!raf && !reduced && visible && !document.hidden && (vel !== 0 || target !== 0)) { last = performance.now(); raf = requestAnimationFrame(tick); } };
  const stop = () => { if (raf) cancelAnimationFrame(raf); raf = 0; };

  motionPreference.addEventListener('change', () => { reduced = motionPreference.matches; if (reduced) { stop(); pose(0, false); draw(); } else run(); });
  const set = rpm => {
    rpm = Number.isFinite(rpm) ? Math.max(0, rpm) : 0;
    const on = rpm > 0;
    target = on ? rpm * Math.PI * 2 / 60 : 0;
    canvas.setAttribute('aria-label', on ? `A hamster wheel turning at ${rpm.toFixed(1)} revolutions per minute` : 'A hamster wheel, at rest');
    cap.classList.toggle('on', on);
    cap.lastElementChild.textContent = on ? `Running, ${rpm.toFixed(1)} rpm` : 'Idle, at rest';
    run();
  };
  document.addEventListener('wheel-rpm', e => set(/** @type {CustomEvent<number>} */ (e).detail));
  document.addEventListener('wheel-offline', () => { target = vel = 0; stop(); pose(0, false); draw(); cap.classList.remove('on'); cap.lastElementChild.textContent = 'Feed offline'; canvas.setAttribute('aria-label', 'A hamster wheel; live feed unavailable'); });
  if (typeof window.__rpm === 'number') set(window.__rpm);

  document.addEventListener('visibilitychange', () => document.hidden ? stop() : run());
  new IntersectionObserver(([e]) => { visible = e.isIntersecting; visible ? run() : stop(); }).observe(stage);
  new ResizeObserver(size).observe(stage);
  size();
}
