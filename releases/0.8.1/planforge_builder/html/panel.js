(function () {
  let hydrating = false;
  let currentSelection = null;

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
    elements.applyMaterialsOnCreate = document.getElementById('applyMaterialsOnCreate');
    elements.wallMaterialName = document.getElementById('wallMaterialName');
    elements.wallMaterialColor = document.getElementById('wallMaterialColor');
    elements.floorMaterialName = document.getElementById('floorMaterialName');
    elements.floorMaterialColor = document.getElementById('floorMaterialColor');
    elements.baseboardMaterialName = document.getElementById('baseboardMaterialName');
    elements.baseboardMaterialColor = document.getElementById('baseboardMaterialColor');
    elements.activateRoomTool = document.getElementById('activateRoomTool');
    elements.activateTool = document.getElementById('activateTool');
    elements.activateDoorTool = document.getElementById('activateDoorTool');
    elements.activateWindowTool = document.getElementById('activateWindowTool');
    elements.generateBaseboards = document.getElementById('generateBaseboards');
    elements.saveSettings = document.getElementById('saveSettings');
    elements.resetSettings = document.getElementById('resetSettings');
    elements.statusMessage = document.getElementById('statusMessage');
    elements.versionTag = document.getElementById('versionTag');
    elements.logPath = document.getElementById('logPath');

    elements.refreshSelection = document.getElementById('refreshSelection');
    elements.selectionTitle = document.getElementById('selectionTitle');
    elements.selectionHint = document.getElementById('selectionHint');
    elements.selectionRoomMeta = document.getElementById('selectionRoomMeta');
    elements.selectedWallEditor = document.getElementById('selectedWallEditor');
    elements.selectedWallLength = document.getElementById('selectedWallLength');
    elements.selectedWallThickness = document.getElementById('selectedWallThickness');
    elements.selectedWallHeight = document.getElementById('selectedWallHeight');
    elements.selectedWallAlignment = document.getElementById('selectedWallAlignment');
    elements.applyWallEdits = document.getElementById('applyWallEdits');
    elements.regenerateSelectedRoom = document.getElementById('regenerateSelectedRoom');
    elements.openingSelect = document.getElementById('openingSelect');
    elements.openingWidth = document.getElementById('openingWidth');
    elements.openingHeight = document.getElementById('openingHeight');
    elements.openingOffset = document.getElementById('openingOffset');
    elements.openingBottom = document.getElementById('openingBottom');
    elements.openingHint = document.getElementById('openingHint');
    elements.applyOpeningEdits = document.getElementById('applyOpeningEdits');
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
      elements.createBaseboardOnClose,
      elements.applyMaterialsOnCreate,
      elements.wallMaterialName,
      elements.wallMaterialColor,
      elements.floorMaterialName,
      elements.floorMaterialColor,
      elements.baseboardMaterialName,
      elements.baseboardMaterialColor
    ].forEach(function (element) {
      element.addEventListener('change', autoSave);
    });

    elements.saveSettings.addEventListener('click', function () {
      saveSettings();
    });

    elements.activateRoomTool.addEventListener('click', function () {
      saveSettings(function () {
        callSketchup('activateRoomTool');
      });
    });

    elements.activateTool.addEventListener('click', function () {
      saveSettings(function () {
        callSketchup('activateWallTool');
      });
    });

    elements.activateDoorTool.addEventListener('click', function () {
      saveSettings(function () {
        callSketchup('activateDoorTool');
      });
    });

    elements.activateWindowTool.addEventListener('click', function () {
      saveSettings(function () {
        callSketchup('activateWindowTool');
      });
    });

    elements.generateBaseboards.addEventListener('click', function () {
      saveSettings(function () {
        callSketchup('generateBaseboards');
      });
    });

    elements.resetSettings.addEventListener('click', function () {
      callSketchup('resetSettings');
    });

    elements.refreshSelection.addEventListener('click', function () {
      callSketchup('refreshSelectionState');
    });

    elements.applyWallEdits.addEventListener('click', function () {
      callSketchup('applyWallEdits', selectedWallPayload());
    });

    elements.regenerateSelectedRoom.addEventListener('click', function () {
      callSketchup('regenerateSelectedRoom');
    });

    elements.applyOpeningEdits.addEventListener('click', function () {
      callSketchup('applyOpeningEdits', selectedOpeningPayload());
    });

    elements.openingSelect.addEventListener('change', function () {
      hydrateOpeningEditor();
    });
  }

  function callSketchup(actionName, payload) {
    if (!window.sketchup || typeof window.sketchup[actionName] !== 'function') {
      return;
    }

    if (typeof payload === 'undefined') {
      window.sketchup[actionName]();
    } else {
      window.sketchup[actionName](payload);
    }
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
      create_baseboard_on_close: elements.createBaseboardOnClose.checked,
      apply_materials_on_create: elements.applyMaterialsOnCreate.checked,
      wall_material_name: elements.wallMaterialName.value,
      wall_material_color: elements.wallMaterialColor.value,
      floor_material_name: elements.floorMaterialName.value,
      floor_material_color: elements.floorMaterialColor.value,
      baseboard_material_name: elements.baseboardMaterialName.value,
      baseboard_material_color: elements.baseboardMaterialColor.value
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
    elements.applyMaterialsOnCreate.checked = !!state.apply_materials_on_create;
    elements.wallMaterialName.value = state.wall_material_name;
    elements.wallMaterialColor.value = state.wall_material_color;
    elements.floorMaterialName.value = state.floor_material_name;
    elements.floorMaterialColor.value = state.floor_material_color;
    elements.baseboardMaterialName.value = state.baseboard_material_name;
    elements.baseboardMaterialColor.value = state.baseboard_material_color;
    elements.versionTag.textContent = 'v' + state.version;
    elements.logPath.textContent = state.log_path || '';
    elements.statusMessage.textContent = state.message || '';
    currentSelection = state.selection || null;
    renderSelection();
    hydrating = false;
  }

  function renderSelection() {
    const selection = currentSelection || {};
    elements.selectionTitle.textContent = selection.title || 'Editor parametrico';
    elements.selectionHint.textContent = selection.hint || 'Selecione uma parede do plugin.';

    if (selection.room) {
      const roomBits = [];
      roomBits.push(selection.room.wall_count + ' paredes');
      roomBits.push(selection.room.has_floor ? 'com piso' : 'sem piso');
      roomBits.push(selection.room.has_baseboard ? 'com rodape' : 'sem rodape');
      elements.selectionRoomMeta.textContent = roomBits.join(' | ');
    } else {
      elements.selectionRoomMeta.textContent = '';
    }

    const wall = selection.wall;
    if (!selection.available || !wall) {
      elements.selectedWallEditor.classList.add('is-hidden');
      resetOpeningEditor([]);
      return;
    }

    elements.selectedWallEditor.classList.remove('is-hidden');
    elements.selectedWallLength.value = wall.length_cm;
    elements.selectedWallThickness.value = wall.wall_thickness_cm;
    elements.selectedWallHeight.value = wall.wall_height_cm;
    elements.selectedWallAlignment.value = wall.alignment;
    resetOpeningEditor(wall.openings || []);
  }

  function resetOpeningEditor(openings) {
    elements.openingSelect.innerHTML = '';

    if (!openings || openings.length === 0) {
      const option = document.createElement('option');
      option.value = '';
      option.textContent = 'Sem portas ou janelas nesta parede';
      elements.openingSelect.appendChild(option);
      setOpeningInputsDisabled(true);
      elements.openingWidth.value = '';
      elements.openingHeight.value = '';
      elements.openingOffset.value = '';
      elements.openingBottom.value = '';
      elements.openingHint.textContent = 'Use as ferramentas de porta e janela para criar novas aberturas nesta parede.';
      return;
    }

    openings.forEach(function (opening) {
      const option = document.createElement('option');
      option.value = opening.id;
      option.textContent = opening.label;
      elements.openingSelect.appendChild(option);
    });

    setOpeningInputsDisabled(false);
    hydrateOpeningEditor();
  }

  function hydrateOpeningEditor() {
    const opening = selectedOpening();
    if (!opening) {
      return;
    }

    elements.openingWidth.value = opening.width_cm;
    elements.openingHeight.value = opening.height_cm;
    elements.openingOffset.value = opening.center_distance_cm;
    elements.openingBottom.value = opening.bottom_height_cm;

    if (opening.kind === 'door') {
      elements.openingBottom.disabled = true;
      elements.openingHint.textContent = 'Portas ficam apoiadas na base da parede. A altura da base e recalculada automaticamente.';
    } else {
      elements.openingBottom.disabled = false;
      elements.openingHint.textContent = 'Janelas aceitam peitoril livre. O topo continua respeitando os limites da parede.';
    }
  }

  function setOpeningInputsDisabled(disabled) {
    elements.openingSelect.disabled = disabled;
    elements.openingWidth.disabled = disabled;
    elements.openingHeight.disabled = disabled;
    elements.openingOffset.disabled = disabled;
    elements.openingBottom.disabled = disabled;
    elements.applyOpeningEdits.disabled = disabled;
  }

  function selectedOpening() {
    if (!currentSelection || !currentSelection.wall || !currentSelection.wall.openings) {
      return null;
    }

    const selectedId = elements.openingSelect.value;
    for (let index = 0; index < currentSelection.wall.openings.length; index += 1) {
      if (currentSelection.wall.openings[index].id === selectedId) {
        return currentSelection.wall.openings[index];
      }
    }

    return currentSelection.wall.openings[0] || null;
  }

  function selectedWallPayload() {
    return {
      wall_thickness_cm: elements.selectedWallThickness.value,
      wall_height_cm: elements.selectedWallHeight.value,
      alignment: elements.selectedWallAlignment.value
    };
  }

  function selectedOpeningPayload() {
    return {
      id: elements.openingSelect.value,
      opening_width_cm: elements.openingWidth.value,
      opening_height_cm: elements.openingHeight.value,
      center_distance_cm: elements.openingOffset.value,
      bottom_height_cm: elements.openingBottom.value
    };
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
