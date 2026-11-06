import React from 'react';
import {Composition} from 'remotion';
import {Main} from './Main';
import timeline from './timeline.json';

export const RemotionRoot: React.FC = () => (
  <Composition id="Main" component={Main} durationInFrames={timeline.frames} fps={timeline.fps} width={1920} height={1080} />
);
