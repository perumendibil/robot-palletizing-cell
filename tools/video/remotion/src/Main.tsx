import React from 'react';
import {AbsoluteFill, OffthreadVideo, interpolate, staticFile, useCurrentFrame, Easing} from 'remotion';
import timeline from './timeline.json';

const FPS = timeline.fps;
const s = (sec: number) => Math.round(sec * FPS);
const ORANGE = '#ff8a1f';
const PANEL = 'rgba(16,19,23,0.84)';
const HEAD = "Bahnschrift, 'Segoe UI', sans-serif";
const BODY = "'Segoe UI', Arial, sans-serif";
const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;
const scene = (id: string) => timeline.scenes.find((x) => x.id === id)!;

// Rotulos de los momentos clave (segundos del video final)
type Cap = {from: number; to: number; title: string; sub?: string; step?: number};
// tiempos (s) de inicio y fin de cada escena, leidos de timeline.json
const st = (id: string) => scene(id).from / FPS;
const en = (id: string) => scene(id).to / FPS;
const CAPTIONS: Cap[] = [
  {from: en('orbit') - 0.9, to: en('two_products') - 0.05, title: 'One robot, two products', sub: 'Box 1 to the Euro pallet  ·  Box 2 to the stacking table', step: 1},
  {from: st('block') + 0.1, to: en('block') + 0.3, title: 'Six boxes, one pick', sub: 'A 3×2 block forms on the table and goes to the half pallet in one move', step: 2},
  {from: st('euro_full') + 0.05, to: en('euro_full') + 0.4, title: 'Euro pallet full', sub: 'A light and a message tell the operator; the robot carries on with box 2', step: 3},
  {from: st('euro_swap') - 0.3, to: en('euro_swap') + 0.4, title: 'Swapped from outside the fence', sub: 'The robot never stops', step: 3},
  {from: st('fill_half1') + 0.6, to: en('fill_half1') - 0.2, title: 'Filling the half pallet', sub: '3 layers  ·  72 boxes'},
  {from: st('liner') - 0.2, to: en('liner') + 0.5, title: 'A liner between layers', sub: 'A cardboard sheet covers every finished layer', step: 4},
  {from: st('half_full') + 0.05, to: en('both_full') - 0.1, title: 'Half pallet full', sub: 'Both pallets are full: the next block waits on the table', step: 5},
  {from: st('new_pallet') - 0.05, to: en('new_pallet') + 0.35, title: 'New pallet', sub: 'The block that was waiting goes first', step: 5},
  {from: st('back') + 0.5, to: en('back') - 0.25, title: 'Euro pallet swapped', sub: 'Back to both products', step: 6},
];
const HUD_FROM = en('orbit') - 0.1;
const HUD_TO = st('end') - 0.2;
const TOTAL_STEPS = 6;

const anim = (f: number, from: number, to: number, inF = 14, outF = 10) => {
  const a = s(from), b = s(to);
  const enter = interpolate(f, [a, a + inF], [0, 1], {...clamp, easing: Easing.out(Easing.cubic)});
  const exit = interpolate(f, [b - outF, b], [1, 0], {...clamp, easing: Easing.in(Easing.cubic)});
  return {visible: f >= a && f <= b, enter, opacity: Math.min(enter, exit)};
};

const LowerThird: React.FC<{c: Cap}> = ({c}) => {
  const f = useCurrentFrame();
  const {visible, enter, opacity} = anim(f, c.from, c.to);
  if (!visible) return null;
  const bar = interpolate(f, [s(c.from), s(c.from) + 18], [0, 1], {...clamp, easing: Easing.out(Easing.cubic)});
  return (
    <div style={{position: 'absolute', left: 64, bottom: 72, opacity, transform: `translateX(${(1 - enter) * -28}px)`}}>
      <div style={{display: 'flex', alignItems: 'stretch', background: PANEL, borderRadius: 4, overflow: 'hidden', boxShadow: '0 8px 30px rgba(0,0,0,.25)'}}>
        <div style={{width: 8, background: ORANGE, transform: `scaleY(${bar})`, transformOrigin: 'bottom'}} />
        <div style={{padding: '22px 36px 24px 28px'}}>
          <div style={{fontFamily: HEAD, fontWeight: 700, fontSize: 50, color: '#fff', letterSpacing: '0.01em', lineHeight: 1.05}}>{c.title}</div>
          {c.sub && <div style={{fontFamily: BODY, fontSize: 28, color: '#c9ced5', marginTop: 10}}>{c.sub}</div>}
        </div>
      </div>
    </div>
  );
};

const StepChip: React.FC = () => {
  const f = useCurrentFrame();
  const c = CAPTIONS.find((x) => x.step && f >= s(x.from) && f <= s(x.to));
  if (!c) return null;
  const {opacity} = anim(f, c.from, c.to);
  return (
    <div style={{position: 'absolute', right: 64, bottom: 72, opacity, background: PANEL, borderRadius: 4, padding: '14px 20px',
      fontFamily: HEAD, fontWeight: 700, fontSize: 24, letterSpacing: '0.14em', color: ORANGE}}>
      {String(c.step).padStart(2, '0')} <span style={{color: '#8b929b'}}>/ {String(TOTAL_STEPS).padStart(2, '0')}</span>
    </div>
  );
};

const TopChip: React.FC = () => {
  const f = useCurrentFrame();
  const {visible, opacity} = anim(f, HUD_FROM, HUD_TO, 18, 14);
  if (!visible) return null;
  return (
    <div style={{position: 'absolute', left: 64, top: 56, opacity, background: 'rgba(16,19,23,0.72)', borderRadius: 4, padding: '12px 20px',
      fontFamily: HEAD, fontWeight: 600, fontSize: 22, letterSpacing: '0.13em', color: '#fff', textTransform: 'uppercase'}}>
      <span style={{color: ORANGE}}>■</span>&nbsp;&nbsp;Palletizing cell · ABB IRB 1600
    </div>
  );
};

const nice = (x: number) => (x < 10 ? Math.round(x).toString() : (Math.round(x / 5) * 5).toString());
const SpeedPill: React.FC = () => {
  const f = useCurrentFrame();
  const factor = (timeline as any).nominal[f] as number | null;
  const {opacity} = anim(f, HUD_FROM, HUD_TO, 18, 14);
  if (factor == null || f < s(HUD_FROM) || f > s(HUD_TO)) return null;
  const fast = factor >= 10;
  return (
    <div style={{position: 'absolute', right: 22, bottom: 16, opacity: opacity * 0.9, fontFamily: BODY, fontSize: 17,
      color: fast ? ORANGE : 'rgba(255,255,255,.9)', background: 'rgba(16,19,23,0.55)', borderRadius: 12, padding: '3px 10px'}}>
      {fast ? '▶▶ ' : ''}≈{nice(factor)}× real time
    </div>
  );
};

const Intro: React.FC = () => {
  const f = useCurrentFrame();
  const {visible, enter, opacity} = anim(f, 0.35, 6.2, 22, 22);
  if (!visible) return null;
  return (
    <AbsoluteFill style={{opacity}}>
      <AbsoluteFill style={{background: 'linear-gradient(90deg, rgba(14,16,20,.80) 0%, rgba(14,16,20,.45) 45%, rgba(14,16,20,0) 75%)'}} />
      <div style={{position: 'absolute', left: 120, top: 360, transform: `translateY(${(1 - enter) * 24}px)`}}>
        <div style={{width: 90 * enter, height: 8, background: ORANGE, marginBottom: 34}} />
        <div style={{fontFamily: HEAD, fontWeight: 700, fontSize: 96, color: '#fff'}}>Robot palletizing cell</div>
        <div style={{fontFamily: BODY, fontSize: 38, color: '#d3d7dd', marginTop: 12}}>ABB IRB 1600 · RobotStudio simulation</div>
      </div>
    </AbsoluteFill>
  );
};

const EndCard: React.FC = () => {
  const f = useCurrentFrame();
  const a = scene('end').from + s(0.2);
  if (f < a) return null;
  const t = interpolate(f, [a, a + 24], [0, 1], {...clamp, easing: Easing.out(Easing.cubic)});
  const line = (d: number) => ({
    opacity: interpolate(f, [a + d, a + d + 16], [0, 1], clamp),
    transform: `translateY(${interpolate(f, [a + d, a + d + 16], [16, 0], {...clamp, easing: Easing.out(Easing.cubic)})}px)`,
  });
  return (
    <AbsoluteFill>
      <AbsoluteFill style={{background: 'linear-gradient(90deg, rgba(12,14,18,.94) 0%, rgba(12,14,18,.82) 55%, rgba(12,14,18,.55) 100%)', opacity: t}} />
      <div style={{position: 'absolute', left: 120, top: 290, color: '#fff'}}>
        <div style={{width: 90 * t, height: 8, background: ORANGE, marginBottom: 34}} />
        <div style={{...line(4), fontFamily: HEAD, fontWeight: 700, fontSize: 92}}>Robot palletizing cell</div>
        <div style={{...line(10), fontFamily: BODY, fontSize: 38, color: '#c9ced5', marginTop: 12}}>ABB IRB 1600 · RobotStudio simulation</div>
        <div style={{...line(20), fontFamily: HEAD, fontWeight: 600, fontSize: 46, marginTop: 56}}>Peru Mendivil &amp; Joaquín Moreno</div>
        <div style={{...line(26), fontFamily: BODY, fontSize: 30, color: '#aab0b8', marginTop: 12}}>Industrial Robotics and Offline Programming · University of Skövde</div>
        <div style={{...line(34), fontFamily: BODY, fontSize: 20, color: '#7f8690', marginTop: 40, letterSpacing: '0.04em'}}>Simulation · time-lapse</div>
      </div>
    </AbsoluteFill>
  );
};

export const Main: React.FC = () => {
  const f = useCurrentFrame();
  const fadeIn = interpolate(f, [0, 12], [1, 0], clamp);
  const fadeOut = interpolate(f, [timeline.frames - 18, timeline.frames - 1], [0, 1], clamp);
  return (
    <AbsoluteFill style={{background: '#000'}}>
      <OffthreadVideo src={staticFile('base.mp4')} muted />
      <Intro />
      <TopChip />
      {CAPTIONS.map((c, i) => <LowerThird key={i} c={c} />)}
      <StepChip />
      <SpeedPill />
      <EndCard />
      <AbsoluteFill style={{background: '#000', opacity: Math.max(fadeIn, fadeOut)}} />
    </AbsoluteFill>
  );
};
