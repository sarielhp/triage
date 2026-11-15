'use strict';
const drawing = document.querySelector('.drawing');
const controls = document.querySelector('.mesh-controls');
if (drawing && controls) {
  controls.hidden = false;
  document.getElementById('mesh-toggle').addEventListener('click', event => {
    const hidden = drawing.classList.toggle('mesh-hidden');
    event.currentTarget.setAttribute('aria-pressed', String(!hidden));
  });
  document.getElementById('vertices-toggle').addEventListener('click', event => {
    const visible = drawing.classList.toggle('points-visible');
    event.currentTarget.setAttribute('aria-pressed', String(visible));
  });
}
