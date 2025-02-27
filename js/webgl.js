let webgl2Supported = (typeof WebGL2RenderingContext !== 'undefined');
let webgl_fallback = false;
let gl;

let webglOptions = {
  alpha: false, //Boolean that indicates if the canvas contains an alpha buffer.
  antialias: false,  //Boolean that indicates whether or not to perform anti-aliasing.
  depth: true,  //Boolean that indicates that the drawing buffer has a depth buffer of at least 16 bits.
  failIfMajorPerformanceCaveat: false,  //Boolean that indicates if a context will be created if the system performance is low.
  powerPreference: "default", //A hint to the user agent indicating what configuration of GPU is suitable for the WebGL context. Possible values are:
  premultipliedAlpha: false,  //Boolean that indicates that the page compositor will assume the drawing buffer contains colors with pre-multiplied alpha.
  preserveDrawingBuffer: false,  //If the value is true the buffers will not be cleared and will preserve their values until cleared or overwritten by the author.
  stencil: true, //Boolean that indicates that the drawing buffer has a stencil buffer of at least 8 bits.
}

if (webgl2Supported) {
  gl = $canvasgl.getContext('webgl2', webglOptions);
  if (!gl) {
    throw new Error('The browser supports WebGL2, but initialization failed.');
  }
}
if (!gl) {
  webgl_fallback = true;
  gl = $canvasgl.getContext('webgl', webglOptions);

  if (!gl) {
    throw new Error('The browser does not support WebGL');
  }

  let vaoExt = gl.getExtension("OES_vertex_array_object");
  if (!vaoExt) {
    throw new Error('The browser supports WebGL, but not the OES_vertex_array_object extension');
  }
  gl.createVertexArray = vaoExt.createVertexArrayOES,
  gl.deleteVertexArray = vaoExt.deleteVertexArrayOES,
  gl.isVertexArray = vaoExt.isVertexArrayOES,
  gl.bindVertexArray = vaoExt.bindVertexArrayOES,
  gl.createVertexArray = vaoExt.createVertexArrayOES;
}
if (!gl) {
  throw new Error('The browser supports WebGL, but initialization failed.');
}

const glShaders = [];
const glPrograms = [];
const glVertexArrays = [];
const glBuffers = [];
const glTextures = [ null ];
const glFramebuffers = [ null ];
const glUniformLocations = [];

const glInitShader = (sourcePtr, sourceLen, type) => {
  const source = readCharStr(sourcePtr, sourceLen);
  const shader = gl.createShader(type);
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    throw "Error compiling shader:" + gl.getShaderInfoLog(shader);
  }
  glShaders.push(shader);
  return glShaders.length - 1;
}
const glLinkShaderProgram = (vertexShaderId, fragmentShaderId) => {
  const program = gl.createProgram();
  gl.attachShader(program, glShaders[vertexShaderId]);
  gl.attachShader(program, glShaders[fragmentShaderId]);
  gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    throw ("Error linking program:" + gl.getProgramInfoLog(program));
  }
  glPrograms.push(program);
  return glPrograms.length - 1;
}

const glViewport = (x, y, width, height) => gl.viewport(x, y, width, height);
const glClearColor = (r, g, b, a) => gl.clearColor(r, g, b, a);
const glEnable = (x) => gl.enable(x);
const glDepthFunc = (x) => gl.depthFunc(x);
const glBlendFunc = (x, y) => gl.blendFunc(x, y);
const glClear = (x) => gl.clear(x);
const glGetAttribLocation = (programId, namePtr, nameLen) => gl.getAttribLocation(glPrograms[programId], readCharStr(namePtr, nameLen));
const glGetUniformLocation = (programId, namePtr, nameLen) => {
  glUniformLocations.push(gl.getUniformLocation(glPrograms[programId], readCharStr(namePtr, nameLen)));
  return glUniformLocations.length - 1;
};
const glUniform4f = (locationId, x, y, z, w) => gl.uniform4fv(glUniformLocations[locationId], [x, y, z, w]);
const glUniformMatrix4fv = (locationId, dataLen, transpose, dataPtr) => {
  const floats = new Float32Array(memory.buffer, dataPtr, dataLen * 16);
  gl.uniformMatrix4fv(glUniformLocations[locationId], transpose, floats);
};
const glUniform1i = (locationId, x) => gl.uniform1i(glUniformLocations[locationId], x);
const glUniform1f = (locationId, x) => gl.uniform1f(glUniformLocations[locationId], x);
const glUniform2f = (locationId, x, y) => gl.uniform2f(glUniformLocations[locationId], x, y);
const glCreateBuffer = () => {
  glBuffers.push(gl.createBuffer());
  return glBuffers.length - 1;
}
const glGenBuffers = (num, dataPtr) => {
  const buffers = new Uint32Array(memory.buffer, dataPtr, num);
  for (let n = 0; n < num; n++) {
    const b = glCreateBuffer();
    buffers[n] = b;
  }
}
const glDetachShader = (program, shader) => {
  gl.detachShader(glPrograms[program], glShaders[shader]);
};
const glDeleteProgram = (id) => {
  gl.deleteProgram(glPrograms[id]);
  glPrograms[id] = undefined;
};
const glDeleteBuffer = (id) => {
  gl.deleteBuffer(glPrograms[id]);
  glPrograms[id] = undefined;
};
const glDeleteBuffers = (num, dataPtr) => {
  const buffers = new Uint32Array(memory.buffer, dataPtr, num);
  for (let n = 0; n < num; n++) {
    gl.deleteBuffer(buffers[n]);
    glBuffers[buffers[n]] = undefined;
  }
};
const glDeleteShader = (id) => {
  gl.deleteShader(glShaders[id]);
  glShaders[id] = undefined;
};
const glBindBuffer = (type, bufferId) => gl.bindBuffer(type, glBuffers[bufferId]);
const glBufferData = (type, count, dataPtr, drawType) => {
  const floats = new Float32Array(memory.buffer, dataPtr, count);
  gl.bufferData(type, floats, drawType);
}
const glUseProgram = (programId) => gl.useProgram(glPrograms[programId]);
const glEnableVertexAttribArray = (x) => gl.enableVertexAttribArray(x);
const glVertexAttribPointer = (attribLocation, size, type, normalize, stride, offset) => {
  gl.vertexAttribPointer(attribLocation, size, type, normalize, stride, offset);
}
const glDrawArrays = (type, offset, count) => gl.drawArrays(type, offset, count);
const createTexture = () => {
  glTextures.push(gl.createTexture());
  return glTextures.length - 1;
};
const glTexImage2DUrl = (textureId, urlPtr, urlLen) => {
  const url = readCharStr(urlPtr, urlLen);
  const image = new Image();
  image.crossOrigin = '';
  image.onload = () => {
    gl.bindTexture(gl.TEXTURE_2D, glTextures[textureId]);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, image);
  }
  image.src = url;
}
const glGenTextures = (num, dataPtr) => {
  const textures = new Uint32Array(memory.buffer, dataPtr, num);
  for (let n = 0; n < num; n++) {
    textures[n] = createTexture();
  }
}
const glDeleteTextures = (num, dataPtr) => {
  const textures = new Uint32Array(memory.buffer, dataPtr, num);
  for (let n = 0; n < num; n++) {
    deleteTexture(textures[n]);
  }
};
const deleteTexture = (id) => {
  gl.deleteTexture(glTextures[id]);
  glTextures[id] = undefined;
};
const glBindTexture = (target, textureId) => {
  if (textureId != 0) {
    gl.bindTexture(target, glTextures[textureId]);
  }
}
const glTexImage2D = (target, level, internalFormat, width, height, border, format, type, dataPtr, dataLen) => {
  if (dataLen == 0) {
    gl.texImage2D(target, level, internalFormat, width, height, border, format, type, null);
  } else {
    const data = new Uint8Array(memory.buffer, dataPtr, dataLen);
    gl.texImage2D(target, level, internalFormat, width, height, border, format, type, data);
  }
};
const glTexSubImage2D = (target, level, xoffset, yoffset, width, height, format, type, dataPtr) => {
  const data = new Uint8Array(memory.buffer, dataPtr);
  gl.texSubImage2D(target, level, xoffset, yoffset, width, height, format, type, data);
}
const glTexParameteri = (target, pname, param) => gl.texParameteri(target, pname, param);
const glActiveTexture = (target) => gl.activeTexture(target);
const glCreateVertexArray = () => {
  glVertexArrays.push(gl.createVertexArray());
  return glVertexArrays.length - 1;
};
const glGenFramebuffers = (num, dataPtr) => {
  const fbs = new Uint32Array(memory.buffer, dataPtr, num);
  for (let n = 0; n < num; n++) {
    glFramebuffers.push(gl.createFramebuffer());
    fbs[n] = glFramebuffers.length - 1;
  }
};
const glBindFramebuffer = (target, framebuffer) => {
  gl.bindFramebuffer(target, glFramebuffers[framebuffer]);
}
const glFramebufferTexture2D = (target, attachment, textarget, texture, level) => {
  gl.framebufferTexture2D(target, attachment, textarget, glTextures[texture], level);
}
const glGenVertexArrays = (num, dataPtr) => {
  const vaos = new Uint32Array(memory.buffer, dataPtr, num);
  for (let n = 0; n < num; n++) {
    const b = glCreateVertexArray();
    vaos[n] = b;
  }
}
const glBindVertexArray = (id) => gl.bindVertexArray(glVertexArrays[id]);
const glPixelStorei = (type, alignment) => gl.pixelStorei(type, alignment);
const glGetError = () => gl.getError();
const glPrintError = () => console.log(gl.getError());

var webgl = {
  glInitShader,
  glLinkShaderProgram,
  glUseProgram,
  glDeleteProgram,
  glDetachShader,
  glDeleteShader,
  glViewport,
  glClearColor,
  glEnable,
  glDepthFunc,
  glBlendFunc,
  glClear,
  glGetAttribLocation,
  glGetUniformLocation,
  glUniform1i,
  glUniform1f,
  glUniform2f,
  glUniform4f,
  glUniformMatrix4fv,
  glCreateBuffer,
  glGenBuffers,
  glDeleteBuffer,
  glDeleteBuffers,
  glBindBuffer,
  glBufferData,
  glEnableVertexAttribArray,
  glVertexAttribPointer,
  glDrawArrays,
  glTexImage2DUrl,
  glGenTextures,
  glDeleteTextures,
  glBindTexture,
  glTexImage2D,
  glTexSubImage2D,
  glTexParameteri,
  glActiveTexture,
  glGenFramebuffers,
  glBindFramebuffer,
  glFramebufferTexture2D,
  glCreateVertexArray,
  glGenVertexArrays,
  glBindVertexArray,
  glPixelStorei,
  glGetError,
  glPrintError,
};