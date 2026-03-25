(function () {
  let hydrating = false;

  const elements = {};

  function cache() {
    elements.snapStep = document.getElementById('snapStep');
    elements.wallThickness = document.getElementById('wallThickness');
    elements.wallHeight = document.getElementById('wallHeight');
    elements.floorThickness = document.getElementById('floorThickness');
    elements.doorWidth = document.getElementById('doorWidth');
    elements.doorHeight = document.getElementById('doorHeight');
    elements.windowWidth = document.getElementById('windowWidth');
    elements.windowHeight = document.getElementById('windowHeight');
    elements.baseboardHeight = document.getElementById('baseboardHeight');
    elements.baseboardDepth = document.getElementById('baseboardDepth');
    elements.alignment = document.getElementById('alignment');
    elements.orthoMode = document.getElementById('orthoMode');
    elements.createFloorOnClose = document.getElementById('createFloorOnClose');
    elements.createBaseboardOnClose = document.getElementById('createBaseboardOnClose');
    elements.activateTool = document.getElementById('activateTool');
    elements.activateDoorTool = document.getElementById('activateDoorTool');
    elements.activateWindowTool = document.getElementById('activateWindowTool');
    elements.generateBaseboards = document.getElementById('generateBaseboards');
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
      elements.floorThickness,
      elements.doorWidth,
      elements.doorHeight,
      elements.windowWidth,
      elements.windowHeight,
      elements.baseboardHeight,
      elements.baseboardDepth,
      elements.alignment,
      elements.orthoMode,
      elements.createFloorOnClose,
      elements.createBaseboardOnClose
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

    elements.activateDoorTool.addEventListener('click', function () {
      saveSettings(function () {
        if (window.sketchup && typeof window.sketchup.activateDoorTool === 'function') {
          window.sketchup.activateDoorTool();
        }
      });
    });

    elements.activateWindowTool.addEventListener('click', function () {
      saveSettings(function () {
        if (window.sketchup && typeof window.sketchup.activateWindowTool === 'function') {
          window.sketchup.activateWindowTool();
        }
      });
    });

    elements.generateBaseboards.addEventListener('click', function () {
      saveSettings(function () {
        if (window.sketchup && typeof window.sketchup.generateBaseboards === 'function') {
          window.sketchup.generateBaseboards();
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
      floor_thickness_cm: elements.floorThickness.value,
      door_width_cm: elements.doorWidth.value,
      door_height_cm: elements.doorHeight.value,
      window_width_cm: elements.windowWidth.value,
      window_height_cm: elements.windowHeight.value,
      baseboard_height_cm: elements.baseboardHeight.value,
      baseboard_depth_cm: elements.baseboardDepth.value,
      alignment: elements.alignment.value,
      ortho_mode: elements.orthoMode.checked,
      create_floor_on_close: elements.createFloorOnClose.checked,
      create_baseboard_on_close: elements.createBaseboardOnClose.checked
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
    elements.floorThickness.value = state.floor_thickness_cm;
    elements.doorWidth.value = state.door_width_cm;
    elements.doorHeight.value = state.door_height_cm;
    elements.windowWidth.value = state.window_width_cm;
    elements.windowHeight.value = state.window_height_cm;
    elements.baseboardHeight.value = state.baseboard_height_cm;
    elements.baseboardDepth.value = state.baseboard_depth_cm;
    elements.alignment.value = state.alignment;
    elements.orthoMode.checked = !!state.ortho_mode;
    elements.createFloorOnClose.checked = !!state.create_floor_on_close;
    elements.createBaseboardOnClose.checked = !!state.create_baseboard_on_close;
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
