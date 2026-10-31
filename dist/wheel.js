// The Squeekchain hamster wheel, rendered with three.js.
// It turns at the live rpm from the hardware feed (app.js dispatches "wheel") and rests when the wheel is idle.
import * as T from './vendor/three.module.min.js';
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
  Object.assign(key.shadow.camera, { left: -3, right: 3, top: 3, bottom: -3, near: 1, far: 14 });
  key.shadow.radius = 5; key.shadow.bias = -0.0004;
  scene.add(key);
  scene.add(new T.HemisphereLight(0xdfe6ee, 0x3a2f24, 0.35));

  const steel = new T.MeshStandardMaterial({ color: 0xc4c7cb, metalness: 0.92, roughness: 0.28 });
  const brass = new T.MeshStandardMaterial({ color: 0xd2a04a, metalness: 0.9, roughness: 0.34 });
  const wood = new T.MeshStandardMaterial({ color: 0x5a4332, metalness: 0, roughness: 0.72 });

  const R = 1, W = 0.62, RUNGS = 28;
  const wheel = new T.Group();
  for (const z of [-W / 2, W / 2]) {
    const ring = new T.Mesh(new T.TorusGeometry(R, 0.03, 16, 120), steel);
    ring.position.z = z; ring.castShadow = true; wheel.add(ring);
  }
  const rungGeo = new T.CylinderGeometry(0.016, 0.016, W, 8);
  for (let i = 0; i < RUNGS; i++) {
    const a = (i / RUNGS) * Math.PI * 2;
    const r = new T.Mesh(rungGeo, steel);
    r.rotation.x = Math.PI / 2;
    r.position.set(Math.cos(a) * R, Math.sin(a) * R, 0);
    r.castShadow = true; wheel.add(r);
  }
  const spokeGeo = new T.BoxGeometry(R, 0.022, 0.022);
  for (let i = 0; i < 6; i++) {
    const a = (i / 6) * Math.PI;
    const s = new T.Mesh(spokeGeo, brass);
    s.rotation.z = a; s.position.z = -W / 2; s.castShadow = true; wheel.add(s);
  }
  const hub = new T.Mesh(new T.CylinderGeometry(0.1, 0.1, 0.14, 32), brass);
  hub.rotation.x = Math.PI / 2; hub.position.z = -W / 2 - 0.02; hub.castShadow = true; wheel.add(hub);
  scene.add(wheel);

  // Stand: one brass arm to the axle, on a wooden base.
  const axle = new T.Mesh(new T.CylinderGeometry(0.035, 0.035, 0.34, 20), brass);
  axle.rotation.x = Math.PI / 2; axle.position.z = -W / 2 - 0.16; axle.castShadow = true; scene.add(axle);
  const arm = new T.Mesh(new T.BoxGeometry(0.1, 1.2, 0.07), brass);
  arm.position.set(0, -0.5, -W / 2 - 0.3); arm.castShadow = true; scene.add(arm);
  const foot = new T.Mesh(new T.BoxGeometry(0.34, 0.07, 0.34), brass);
  foot.position.set(0, -1.12, -W / 2 - 0.3); foot.castShadow = true; scene.add(foot);
  const base = new T.Mesh(new T.BoxGeometry(2.5, 0.12, 1.5), wood);
  base.position.set(0, -1.19, -0.1); base.castShadow = true; base.receiveShadow = true; scene.add(base);
  const floor = new T.Mesh(new T.PlaneGeometry(14, 14), new T.ShadowMaterial({ opacity: 0.32 }));
  floor.rotation.x = -Math.PI / 2; floor.position.y = -1.25; floor.receiveShadow = true; scene.add(floor);

  wheel.rotation.z = 0.2;
  scene.rotation.y = -0.62;

  const size = () => {
    const w = stage.clientWidth, h = stage.clientHeight; if (!w || !h) return;
    renderer.setPixelRatio(Math.min(devicePixelRatio || 1, 2));
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    const d = 7.2 * Math.max(1, 1.25 / camera.aspect);
    camera.position.set(0.9 * d / 7.2, 1.3 * d / 7.2, d);
    camera.lookAt(0.35, -0.1, 0);
    camera.updateProjectionMatrix();
    draw();
  };
  const draw = () => renderer.render(scene, camera);

  // Angular velocity eases toward the live rpm so the wheel spins up and coasts down like a real one.
  let target = 0, vel = 0, raf = 0, last = 0, visible = true;
  const tick = now => {
    const dt = Math.min(0.05, (now - last) / 1000 || 0); last = now;
    vel += (target - vel) * (1 - Math.exp(-dt * 2.2));
    if (target === 0 && Math.abs(vel) < 0.002) vel = 0;
    wheel.rotation.z -= vel * dt;
    draw();
    raf = vel !== 0 || target !== 0 ? requestAnimationFrame(tick) : 0;
  };
  const run = () => { if (!raf && !reduced && visible && !document.hidden && (vel !== 0 || target !== 0)) { last = performance.now(); raf = requestAnimationFrame(tick); } };
  const stop = () => { if (raf) cancelAnimationFrame(raf); raf = 0; };
  motionPreference.addEventListener('change', () => { reduced = motionPreference.matches; reduced ? stop() : run(); });

  const set = rpm => {
    const on = rpm > 0;
    target = on ? rpm * Math.PI * 2 / 60 : 0;
    canvas.setAttribute('aria-label', on ? `A hamster wheel turning at ${rpm.toFixed(1)} revolutions per minute` : 'A hamster wheel, at rest');
    cap.classList.toggle('on', on);
    cap.lastElementChild.textContent = on ? `Running, ${rpm.toFixed(1)} rpm` : 'Idle, at rest';
    run();
  };
  document.addEventListener('wheel-rpm', e => set(/** @type {CustomEvent<number>} */ (e).detail));
  document.addEventListener('wheel-offline', () => { target = 0; vel = 0; stop(); cap.classList.remove('on'); cap.lastElementChild.textContent = 'Feed offline'; canvas.setAttribute('aria-label', 'A hamster wheel; live feed unavailable'); });
  if (typeof window.__rpm === 'number') set(window.__rpm);

  document.addEventListener('visibilitychange', () => document.hidden ? stop() : run());
  new IntersectionObserver(([e]) => { visible = e.isIntersecting; visible ? run() : stop(); }).observe(stage);
  new ResizeObserver(size).observe(stage);
  size();
}
