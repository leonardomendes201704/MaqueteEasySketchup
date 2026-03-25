(function () {
  let hydrating = false;

  const elements = {};

  function cache() {
    elements.snapStep = document.getElementById('snapStep');
    elements.wallThickness = document.getElementById('wallThickness');
    elements.wallHeight = document.getElementById('wallHeight');
    elements.alignment = document.getElementById('alignment');
    elements.orthoMode = document.getElementById('orthoMode');
    elements.activateTool = document.getElementById('activateTool');
    elements.saveSettings = document.getElementById('saveSettings');
    elements.resetSettings = document.getElementById('resetSettings');
    elements.statusMessage = document.getElementById('statusMessage');
    elements.versionTag = document.getElementById('versionTag');
    elements.logPath = document.getElementById('logPath');
  }

  function bind() {
    [
      elements.snapStep,
      elements.wallThickness,
      elements.wallHeight,
      elements.alignment,
      elements.orthoMode
    ].forEach(function (element) {
      element.addEventListener('change', autoSave);
    });

    elements.saveSettings.addEventListener('click', function () {
      saveSettings();
    });

    elements.activateTool.addEventListener('click', function () {
      saveSettings(function () {
        if (window.sketchup && typeof window.sketchup.activateWallTool === 'function') {
          window.sketchup.activateWallTool();
        }
      });
    });

    elements.resetSettings.addEventListener('click', function () {
      if (window.sketchup && typeof window.sketchup.resetSettings === 'function') {
        window.sketchup.resetSettings();
      }
    });
  }

  function autoSave() {
    if (hydrating) {
      return;
    }

    saveSettings();
  }

  function payload() {
    return {
      snap_step_cm: elements.snapStep.value,
      wall_thickness_cm: elements.wallThickness.value,
      wall_height_cm: elements.wallHeight.value,
      alignment: elements.alignment.value,
      ortho_mode: elements.orthoMode.checked
    };
  }

  function saveSettings(afterSave) {
    if (!window.sketchup || typeof window.sketchup.saveSettings !== 'function') {
      return;
    }

    window.sketchup.saveSettings(payload());

    if (typeof afterSave === 'function') {
      window.setTimeout(afterSave, 40);
    }
  }

  function bootstrap(state) {
    hydrating = true;
    elements.snapStep.value = state.snap_step_cm;
    elements.wallThickness.value = state.wall_thickness_cm;
    elements.wallHeight.value = state.wall_height_cm;
    elements.alignment.value = state.alignment;
    elements.orthoMode.checked = !!state.ortho_mode;
    elements.versionTag.textContent = 'v' + state.version;
    elements.logPath.textContent = state.log_path || '';
    elements.statusMessage.textContent = state.message || '';
    hydrating = false;
  }

  document.addEventListener('DOMContentLoaded', function () {
    cache();
    bind();

    window.PlanForgePanel = {
      bootstrap: bootstrap
    };

    if (window.sketchup && typeof window.sketchup.ready === 'function') {
      window.sketchup.ready();
    }
  });
})();
