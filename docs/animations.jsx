/**
 * Animations — Timeline-based animation engine for React.
 * Load via: <script type="text/babel" src="animations.jsx"></script>
 *
 * Provides: Stage, Sprite, useTime(), useSprite(), Easing, interpolate()
 *
 * Usage:
 *   <Stage duration={5} width={1920} height={1080}>
 *     <Sprite start={0} end={2}>
 *       <div style={{ background: 'red', width: 100, height: 100 }}>Fade in</div>
 *     </Sprite>
 *   </Stage>
 */

const AnimationsContext = React.createContext({ time: 0, duration: 1, sprite: null });

function useTime() {
  return React.useContext(AnimationsContext).time;
}

function useSprite() {
  return React.useContext(AnimationsContext).sprite ?? { start: 0, end: 1, progress: 0 };
}

const Easing = {
  linear: (t) => t,
  easeIn: (t) => t * t,
  easeOut: (t) => t * (2 - t),
  easeInOut: (t) => (t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t),
  bounce: (t) => {
    const n1 = 7.5625, d1 = 2.75;
    if (t < 1 / d1) return n1 * t * t;
    if (t < 2 / d1) return n1 * (t -= 1.5 / d1) * t + 0.75;
    if (t < 2.5 / d1) return n1 * (t -= 2.25 / d1) * t + 0.9375;
    return n1 * (t -= 2.625 / d1) * t + 0.984375;
  },
  elastic: (t) => {
    if (t === 0 || t === 1) return t;
    return -Math.pow(2, 10 * (t - 1)) * Math.sin((t - 1.1) * 5 * Math.PI);
  },
};

function interpolate(start, end, progress, easing = Easing.linear) {
  const t = easing(Math.max(0, Math.min(1, progress)));
  return start + (end - start) * t;
}

function Sprite({ children, start = 0, end = 1, easing = 'linear', style = {} }) {
  const { time } = React.useContext(AnimationsContext);
  const duration = end - start;
  const easingFn = Easing[easing] || Easing.linear;

  let opacity = 1;
  if (time < start) opacity = 0;
  else if (time > end) opacity = 0;
  else if (time < start + 0.3) opacity = easingFn((time - start) / 0.3);
  else if (time > end - 0.3) opacity = easingFn((time - end + 0.3) / 0.3);

  const progress = duration > 0 ? Math.max(0, Math.min(1, (time - start) / duration)) : 0;
  const sprite = { start, end, progress, easing };

  return React.createElement(AnimationsContext.Provider, { value: { ...React.useContext(AnimationsContext), sprite } },
    React.createElement('div', {
      style: { ...style, opacity, position: 'absolute', inset: 0 },
      'data-sprite-start': start,
      'data-sprite-end': end,
    }, children)
  );
}

function Stage({ children, duration = 5, width = 1920, height = 1080 }) {
  const [playing, setPlaying] = React.useState(false);
  const [time, setTime] = React.useState(0);
  const [scale, setScale] = React.useState(Math.min(window.innerWidth / width, window.innerHeight / height) * 0.9);
  const rafRef = React.useRef(null);
  const startRef = React.useRef(null);

  React.useEffect(() => {
    const onResize = () => setScale(Math.min(window.innerWidth / width, window.innerHeight / height) * 0.9);
    window.addEventListener('resize', onResize);
    return () => window.removeEventListener('resize', onResize);
  }, [width, height]);

  const play = React.useCallback(() => {
    setPlaying(true);
    startRef.current = performance.now() - time * 1000;
  }, [time]);

  const pause = React.useCallback(() => {
    setPlaying(false);
    if (rafRef.current) cancelAnimationFrame(rafRef.current);
  }, []);

  React.useEffect(() => {
    if (!playing) return;
    const tick = (now) => {
      const elapsed = (now - startRef.current) / 1000;
      if (elapsed >= duration) {
        setTime(duration);
        setPlaying(false);
        return;
      }
      setTime(elapsed);
      rafRef.current = requestAnimationFrame(tick);
    };
    rafRef.current = requestAnimationFrame(tick);
    return () => { if (rafRef.current) cancelAnimationFrame(rafRef.current); };
  }, [playing, duration]);

  return React.createElement('div', {
    style: { width: '100vw', height: '100vh', background: '#000', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center' }
  },
    React.createElement(AnimationsContext.Provider, { value: { time, duration } },
      React.createElement('div', {
        style: { width: `${width}px`, height: `${height}px`, transform: `scale(${scale})`, transformOrigin: 'center center', position: 'relative', overflow: 'hidden' }
      }, children)
    ),
    // Controls
    React.createElement('div', {
      style: { marginTop: '16px', display: 'flex', alignItems: 'center', gap: '12px', color: '#fff', fontFamily: 'system-ui, sans-serif', fontSize: '13px' }
    },
      React.createElement('button', {
        onClick: playing ? pause : play,
        style: { padding: '6px 16px', borderRadius: '6px', border: '1px solid rgba(255,255,255,.3)', background: 'rgba(255,255,255,.1)', color: '#fff', cursor: 'pointer' }
      }, playing ? '⏸ Pause' : '▶ Play'),
      React.createElement('input', {
        type: 'range', min: 0, max: duration, step: 0.01, value: time,
        onChange: (e) => setTime(parseFloat(e.target.value)),
        style: { width: '300px', accentColor: '#fff' }
      }),
      React.createElement('span', null, `${time.toFixed(2)}s / ${duration}s`)
    )
  );
}

Object.assign(window, { Stage, Sprite, useTime, useSprite, Easing, interpolate, AnimationsContext });
