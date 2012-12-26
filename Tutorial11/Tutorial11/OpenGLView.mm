//
//  OpenGLView.m
//  Tutorial11
//
//  Created by kesalin@gmail.com on 12-12-24.
//  Copyright (c) 2012 年 http://blog.csdn.net/kesalin/. All rights reserved.
//

#import "OpenGLView.h"
#import "GLESUtils.h"
#import "Quaternion.h"
#import "TextureManager.h"

//
// DrawableVBO implementation
//
@implementation DrawableVBO

@synthesize vertexBuffer, lineIndexBuffer, triangleIndexBuffer;
@synthesize vertexSize, lineIndexCount, triangleIndexCount;

- (void) cleanup
{
    if (vertexBuffer != 0) {
        glDeleteBuffers(1, &vertexBuffer);
        vertexBuffer = 0;
    }
    
    if (lineIndexBuffer != 0) {
        glDeleteBuffers(1, &lineIndexBuffer);
        lineIndexBuffer = 0;
    }
    
    if (triangleIndexBuffer) {
        glDeleteBuffers(1, &triangleIndexBuffer);
        triangleIndexBuffer = 0;
    }
}

@end

//
// OpenGLView anonymous category
//
@interface OpenGLView()
{
    NSMutableArray * _vboArray; 
    DrawableVBO * _currentVBO;
    
    ivec2 _fingerStart;
    Quaternion _orientation;
    Quaternion _previousOrientation;
    KSMatrix4 _rotationMatrix;
}

- (void)setupLayer;
- (void)setupContext;
- (void)setupBuffers;
- (void)destoryBuffer:(GLuint *)buffer;
- (void)destoryBuffers;

- (void)setupProgram;
- (void)setupProjection;
- (void)setupLight;

- (void)setTextureParameter;
- (void)setupTexture;

- (void)setupVBOs;
- (void)destoryVBOs;

- (vec3)mapToSphere:(ivec2) touchpoint;
- (void)updateSurfaceTransform;
- (void)resetRotation;

@end

//
// OpenGLView implementation
//
@implementation OpenGLView

@synthesize textureIndex = _textureIndex;
@synthesize wrapMode = _wrapMode;
@synthesize filterMode = _filterMode;

#pragma mark- Initilize GL

+ (Class)layerClass {
    // Support for OpenGL ES
    return [CAEAGLLayer class];
}

- (void)setupLayer
{
    _eaglLayer = (CAEAGLLayer*) self.layer;
    
    // Make CALayer visibale
    _eaglLayer.opaque = YES;
    
    // Set drawable properties
    _eaglLayer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:
                                    [NSNumber numberWithBool:NO], kEAGLDrawablePropertyRetainedBacking, kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat, nil];
}

- (void)setupContext
{
    // Set OpenGL version, here is OpenGL ES 2.0 
    EAGLRenderingAPI api = kEAGLRenderingAPIOpenGLES2;
    _context = [[EAGLContext alloc] initWithAPI:api];
    if (!_context) {
        NSLog(@" >> Error: Failed to initialize OpenGLES 2.0 context");
        exit(1);
    }
    
    // Set OpenGL context
    if (![EAGLContext setCurrentContext:_context]) {
        _context = nil;
        NSLog(@" >> Error: Failed to set current OpenGL context");
        exit(1);
    }
}

- (void)setupBuffers
{
    // Setup color render buffer
    //
    glGenRenderbuffers(1, &_colorRenderBuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, _colorRenderBuffer);
    [_context renderbufferStorage:GL_RENDERBUFFER fromDrawable:_eaglLayer];
    
    // Setup depth render buffer
    //
    int width, height;
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &width);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &height);
    
    // Create a depth buffer that has the same size as the color buffer.
    glGenRenderbuffers(1, &_depthRenderBuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, _depthRenderBuffer);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, width, height);
    
    // Setup frame buffer
    //
    glGenFramebuffers(1, &_frameBuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, _frameBuffer);
    
    // Attach color render buffer and depth render buffer to frameBuffer
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                              GL_RENDERBUFFER, _colorRenderBuffer);
    
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT,
                              GL_RENDERBUFFER, _depthRenderBuffer);
    
    // Set color render buffer as current render buffer
    //
    glBindRenderbuffer(GL_RENDERBUFFER, _colorRenderBuffer);
}

- (void)destoryBuffer:(GLuint *)buffer
{
    if (buffer && *buffer != 0) {
        glDeleteRenderbuffers(1, buffer);
        *buffer = 0;
    }
}

- (void)destoryBuffers
{
    [self destoryBuffer: &_depthRenderBuffer];
    [self destoryBuffer: &_colorRenderBuffer];
    [self destoryBuffer: &_frameBuffer];
}

- (void)cleanup
{   
    [[TextureManager instance] cleanup];

    [self destoryVBOs];

    [self destoryBuffers];
    
    if (_programHandle != 0) {
        glDeleteProgram(_programHandle);
        _programHandle = 0;
    }

    if (_context && [EAGLContext currentContext] == _context)
        [EAGLContext setCurrentContext:nil];
    
    _context = nil;
}

- (void)setupProgram
{
    // Load shaders
    //
    NSString * vertexShaderPath = [[NSBundle mainBundle] pathForResource:@"VertexShader"
                                                                  ofType:@"glsl"];
    NSString * fragmentShaderPath = [[NSBundle mainBundle] pathForResource:@"FragmentShader"
                                                                    ofType:@"glsl"];
    
    _programHandle = [GLESUtils loadProgram:vertexShaderPath
                 withFragmentShaderFilepath:fragmentShaderPath];
    if (_programHandle == 0) {
        NSLog(@" >> Error: Failed to setup program.");
        return;
    }
    
    glUseProgram(_programHandle);
    
    // Get the attribute and uniform slot from program
    //
    _projectionSlot = glGetUniformLocation(_programHandle, "projection");
    _modelViewSlot = glGetUniformLocation(_programHandle, "modelView");
    _normalMatrixSlot = glGetUniformLocation(_programHandle, "normalMatrix");
    _lightPositionSlot = glGetUniformLocation(_programHandle, "vLightPosition");
    _ambientSlot = glGetUniformLocation(_programHandle, "vAmbientMaterial");
    _specularSlot = glGetUniformLocation(_programHandle, "vSpecularMaterial");
    _shininessSlot = glGetUniformLocation(_programHandle, "shininess");
    
    _positionSlot = glGetAttribLocation(_programHandle, "vPosition");
    _normalSlot = glGetAttribLocation(_programHandle, "vNormal");
    _diffuseSlot = glGetAttribLocation(_programHandle, "vDiffuseMaterial");
    
    _textureCoordSlot = glGetAttribLocation(_programHandle, "vTextureCoord");
    _sampler0Slot = glGetUniformLocation(_programHandle, "Sampler0");
    _sampler1Slot = glGetUniformLocation(_programHandle, "Sampler1");
}

#pragma mark - Surface

- (void)setCurrentSurface:(int)index
{
    index = index % [_vboArray count];
    _currentVBO = [_vboArray objectAtIndex:index];
    
    [self resetRotation];

    [self render];
}

- (DrawableVBO *)createVBOsForCube
{
    const GLfloat vertices[] = {
        -1.5f, -1.5f, 1.5f, 0, 0, 1, 0, 1,
        -1.5f, 1.5f, 1.5f, 0, 0, 1, 0, 0,
        1.5f, 1.5f, 1.5f, 0, 0, 1, 1, 0,
        1.5f, -1.5f, 1.5f, 0, 0, 1, 1, 1,
        
        1.5f, -1.5f, -1.5f, 0.577350, -0.577350, -0.577350, 0, 1,
        1.5f, 1.5f, -1.5f, 0.577350, 0.577350, -0.577350, 0, 0,
        -1.5f, 1.5f, -1.5f, -0.577350, 0.577350, -0.577350, 1, 0,
        -1.5f, -1.5f, -1.5f, -0.577350, -0.577350, -0.577350, 1, 1,
        
        -1.5f, -1.5f, -1.5f, -0.577350, -0.577350, -0.577350, 0, 1,
        -1.5f, 1.5f, -1.5f, -0.577350, 0.577350, -0.577350, 0, 0,
        -1.5f, 1.5f, 1.5f, -0.577350, 0.577350, 0.577350, 1, 0,
        -1.5f, -1.5f, 1.5f, -0.577350, -0.577350, 0.577350, 1, 1,
        
        1.5f, -1.5f, 1.5f, 0.577350, -0.577350, 0.577350, 0, 1,
        1.5f, 1.5f, 1.5f, 0.577350, 0.577350, 0.577350, 0, 0,
        1.5f, 1.5f, -1.5f, 0.577350, 0.577350, -0.577350, 1, 0,
        1.5f, -1.5f, -1.5f, 0.577350, -0.577350, -0.577350, 1, 1,
        
        -1.5f, 1.5f, 1.5f, 0, 1, 0, 0, 2,
        -1.5f, 1.5f, -1.5f, 0, 1, 0, 0, 0,
        1.5f, 1.5f, -1.5f, 0, 1, 0, 2, 0,
        1.5f, 1.5f, 1.5f, 0, 1, 0, 2, 2,
        
        -1.5f, -1.5f, -1.5f, -0.577350, -0.577350, -0.577350, 0, 1,
        -1.5f, -1.5f, 1.5f, -0.577350, -0.577350, 0.577350, 0, 0,
        1.5f, -1.5f, 1.5f, 0.577350, -0.577350, 0.577350, 1, 0,
        1.5f, -1.5f, -1.5f, 0.577350, -0.577350, -0.577350, 1, 1
    };
    
    const GLushort indices[] = {
        // Front face
        0, 1, 3, 1, 2, 3,
        
        // Back face
        7, 5, 4, 7, 6, 5,
        
        // Left face
        8, 9, 10, 8, 10, 11,
        
        // Right face
        12, 13, 14, 12, 14, 15,
        
        // Up face
        16, 17, 18, 16, 18, 19,
        
        // Down face
        20, 21, 22, 20, 22, 23
    };
    
    // Create the VBO for the vertice.
    //
    int vertexSize = 8;
    GLuint vertexBuffer;
    glGenBuffers(1, &vertexBuffer);
    glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer);
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
    
    // Create the VBO for the triangle indice
    //
    int triangleIndexCount = sizeof(indices)/sizeof(indices[0]);
    GLuint triangleIndexBuffer; 
    glGenBuffers(1, &triangleIndexBuffer);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, triangleIndexBuffer);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, triangleIndexCount * sizeof(GLushort), indices, GL_STATIC_DRAW);
    
    DrawableVBO * vbo = [[DrawableVBO alloc] init];
    vbo.vertexBuffer = vertexBuffer;
    vbo.triangleIndexBuffer = triangleIndexBuffer;
    vbo.vertexSize = vertexSize;
    vbo.triangleIndexCount = triangleIndexCount;
    
    return vbo;
}

- (void)setupVBOs
{
    if (_vboArray == nil) {
        _vboArray = [[NSMutableArray alloc] init];
        
        DrawableVBO * vbo = [self createVBOsForCube];
        [_vboArray addObject:vbo];
        vbo = nil;
        
        [self setCurrentSurface:0];
    } 
}

- (void)destoryVBOs
{
    for (DrawableVBO * vbo in _vboArray) {
        [vbo cleanup];
    }
    _vboArray = nil;
    
    _currentVBO = nil;
}


#pragma mark - Draw object

-(void)setupProjection
{
    float width = self.frame.size.width;
    float height = self.frame.size.height;
    
    // Generate a perspective matrix with a 60 degree FOV
    //
    ksMatrixLoadIdentity(&_projectionMatrix);
    float aspect = width / height;
    ksPerspective(&_projectionMatrix, 60.0, aspect, 4.0f, 12.0f);
    
    // Load projection matrix
    glUniformMatrix4fv(_projectionSlot, 1, GL_FALSE, (GLfloat*)&_projectionMatrix.m[0][0]);
    
    // Note: Disable depth test and cull face for texture blending.
    //
    glDisable(GL_CULL_FACE);
    glDisable(GL_DEPTH_TEST);
}

- (void)setupLight
{
    // Set up some default material parameters.
    //
    glUniform4f(_ambientSlot, 0.04f, 0.04f, 0.04f, 0.5);
    glUniform4f(_specularSlot, 0.5, 0.5, 0.5, 0.5);
    glUniform1f(_shininessSlot, 50);
                 
    // Initialize various state.
    //
    glEnableVertexAttribArray(_positionSlot);
    glEnableVertexAttribArray(_normalSlot);
    
    glUniform3f(_lightPositionSlot, 0.0, 0.0, 5.0);
    
    glVertexAttrib4f(_diffuseSlot, 0.8, 0.8, 0.8, 0.5);
}

- (void)setImageTexture:(TextureLoader *)loader level:(GLuint)level
{
    void* pixels = [loader imageData];
    CGSize size = [loader imageSize];
    
    GLenum format;
    TextureFormat tf = [loader textureFormat];
    switch (tf) {
        case TextureFormatGray:
            format = GL_LUMINANCE;
            break;
        case TextureFormatGrayAlpha:
            format = GL_LUMINANCE_ALPHA;
            break;
        case TextureFormatRGB:
            format = GL_RGB;
            break;
        case TextureFormatRGBA:
            format = GL_RGBA;
            break;
            
        default:
            NSLog(@"ERROR: invalid texture format! %d", tf);
            break;
    }
    
    GLenum type;
    int bitsPerComponent = [loader bitsPerComponent];
    switch (bitsPerComponent) {
        case 8:
            type = GL_UNSIGNED_BYTE;
            break;
        case 4:
            if (format == GL_RGBA) {
                type = GL_UNSIGNED_SHORT_4_4_4_4;
                break;
            }
            // fall through
        default:
            NSLog(@"ERROR: invalid texture format! %d, bitsPerComponent %d", tf, bitsPerComponent);
            break;
    }
    
    glTexImage2D(GL_TEXTURE_2D, level, format, size.width, size.height, 0, format, type, pixels);
    
    glGenerateMipmap(GL_TEXTURE_2D);
}

- (void)setTextureParameter
{
    // It can be GL_NICEST or GL_FASTEST or GL_DONT_CARE. GL_DONT_CARE by default.
    //
    glHint(GL_GENERATE_MIPMAP_HINT, GL_NICEST);
    
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, _filterMode); 
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, _filterMode);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, _wrapMode);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, _wrapMode);
}

- (void)setupTexture
{
    // Load image data from resource file.
    //
    TextureLoader * woodenLoader = [[TextureManager instance] loadImage:@"wooden.png"];
    TextureLoader * flowerLoader = [[TextureManager instance] loadImage:@"flower.jpg"];
    
    _wrapMode = GL_REPEAT;
    _filterMode = GL_LINEAR;
    
    // Set the active sampler to stage 0.
    //
    GLuint level = 0;
	glActiveTexture(GL_TEXTURE0);
    glUniform1i(_sampler0Slot, level);
	
    // Wooden Texture
    //
    glGenTextures(1, &_woodenTexture);
    glBindTexture(GL_TEXTURE_2D, _woodenTexture);

    [self setTextureParameter];
    
    [self setImageTexture:woodenLoader level:level];
    
    // Set the active sampler to stage 1.
    //
    level = 1;
	glActiveTexture(GL_TEXTURE1);
    glUniform1i(_sampler1Slot, level);
    
    // Flower Texture
    //
    glGenTextures(1, &_flowerTexture);
    glBindTexture(GL_TEXTURE_2D, _flowerTexture);
    
    [self setTextureParameter];
    
    [self setImageTexture:flowerLoader level:level];
    
    // Setup blend state
    //
    glEnableVertexAttribArray(_textureCoordSlot);
    glEnable(GL_BLEND);
    //glBlendFunc(GL_DST_ALPHA, GL_ONE_MINUS_DST_ALPHA);
}

- (void)resetRotation
{
    ksMatrixLoadIdentity(&_rotationMatrix);
    _previousOrientation.ToIdentity();
    _orientation.ToIdentity();
}

- (void)updateSurfaceTransform
{
    ksMatrixLoadIdentity(&_modelViewMatrix);
    
    ksTranslate(&_modelViewMatrix, 0.0, 0.0, -8);
    
    ksMatrixMultiply(&_modelViewMatrix, &_rotationMatrix, &_modelViewMatrix);
    
    // Load the model-view matrix
    glUniformMatrix4fv(_modelViewSlot, 1, GL_FALSE, (GLfloat*)&_modelViewMatrix.m[0][0]);
    
    // Load the normal matrix.
    // It's orthogonal, so its Inverse-Transpose is itself!
    //
    KSMatrix3 normalMatrix3;
    ksMatrix4ToMatrix3(&normalMatrix3, &_modelViewMatrix);
    glUniformMatrix3fv(_normalMatrixSlot, 1, GL_FALSE, (GLfloat*)&normalMatrix3.m[0][0]);
}

- (void)drawSurface
{
    if (_currentVBO == nil)
        return;
    
    int stride = [_currentVBO vertexSize] * sizeof(GLfloat);
    const GLvoid* normalOffset = (const GLvoid*)(3 * sizeof(GLfloat));
    const GLvoid* texCoordOffset = (const GLvoid*)(6 * sizeof(GLfloat));
    
    glBindBuffer(GL_ARRAY_BUFFER, [_currentVBO vertexBuffer]);
    glVertexAttribPointer(_positionSlot, 3, GL_FLOAT, GL_FALSE, stride, 0);
    glVertexAttribPointer(_normalSlot, 3, GL_FLOAT, GL_FALSE, stride, normalOffset);
    
    glVertexAttribPointer(_textureCoordSlot, 2, GL_FLOAT, GL_FALSE, stride, texCoordOffset);
    
    // Draw the triangles.
    //
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, [_currentVBO triangleIndexBuffer]);
    glDrawElements(GL_TRIANGLES, [_currentVBO triangleIndexCount], GL_UNSIGNED_SHORT, 0);
}

- (void)render
{
    if (_context == nil)
        return;
    
    glClearColor(0.0f, 1.0f, 0.0f, 1);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    
    // Setup viewport
    //
    glViewport(0, 0, self.frame.size.width, self.frame.size.height);    
    
    [self updateSurfaceTransform];
    [self drawSurface];

    [_context presentRenderbuffer:GL_RENDERBUFFER];
}

#pragma mark

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self setupLayer];        
        [self setupContext];
        [self setupProgram];
        [self setupProjection];
        
        [self setupLight];
        
        [self setupTexture];
        
        [self resetRotation];
    }

    return self;
}

- (void)layoutSubviews
{
    [EAGLContext setCurrentContext:_context];
    glUseProgram(_programHandle);

    [self destoryBuffers];
    
    [self setupBuffers];
    
    [self setupVBOs];
    
    [self render];
}

#pragma mark - Touch events

- (void) touchesBegan: (NSSet*) touches withEvent: (UIEvent*) event
{
    UITouch* touch = [touches anyObject];
    CGPoint location  = [touch locationInView: self];
    
    _fingerStart = ivec2(location.x, location.y);
    _previousOrientation = _orientation;
}

- (void) touchesEnded: (NSSet*) touches withEvent: (UIEvent*) event
{
    UITouch* touch = [touches anyObject];
    CGPoint location  = [touch locationInView: self];
    ivec2 touchPoint = ivec2(location.x, location.y);
    
    vec3 start = [self mapToSphere:_fingerStart];
    vec3 end = [self mapToSphere:touchPoint];
    Quaternion delta = Quaternion::CreateFromVectors(start, end);
    _orientation = delta.Rotated(_previousOrientation);
    _orientation.ToMatrix4(&_rotationMatrix);

    [self render];
}

- (void) touchesMoved: (NSSet*) touches withEvent: (UIEvent*) event
{
    UITouch* touch = [touches anyObject];
    CGPoint location  = [touch locationInView: self];
    ivec2 touchPoint = ivec2(location.x, location.y);
    
    vec3 start = [self mapToSphere:_fingerStart];
    vec3 end = [self mapToSphere:touchPoint];
    Quaternion delta = Quaternion::CreateFromVectors(start, end);
    _orientation = delta.Rotated(_previousOrientation);
    _orientation.ToMatrix4(&_rotationMatrix);
    
    [self render];
}

- (vec3) mapToSphere:(ivec2) touchpoint
{
    ivec2 centerPoint = ivec2(self.frame.size.width/2, self.frame.size.height/2);
    float radius = self.frame.size.width/3;
    float safeRadius = radius - 1;
    
    vec2 p = touchpoint - centerPoint;
    
    // Flip the Y axis because pixel coords increase towards the bottom.
    p.y = -p.y;
    
    if (p.Length() > safeRadius) {
        float theta = atan2(p.y, p.x);
        p.x = safeRadius * cos(theta);
        p.y = safeRadius * sin(theta);
    }
    
    float z = sqrt(radius * radius - p.LengthSquared());
    vec3 mapped = vec3(p.x, p.y, z);
    return mapped / radius;
}

#pragma mark - Properties

-(void)setWrapMode:(GLint)wrapMode
{
    if (wrapMode == 0) {
        _wrapMode = GL_REPEAT;
    }
    else if (wrapMode == 1) {
        _wrapMode = GL_CLAMP_TO_EDGE;
    }
    else {
        _wrapMode = GL_MIRRORED_REPEAT;
    }
    
    [self setTextureParameter];

    [self render];
}

-(void)setFilterMode:(GLint)filterMode
{
    if (filterMode == 0) {
        _filterMode = GL_LINEAR;
    }
    else if (filterMode == 1) {
        _filterMode = GL_NEAREST;
    }
    else if (filterMode == 2){
        _filterMode = GL_LINEAR_MIPMAP_NEAREST;
    }
    else if (filterMode == 3){
        _filterMode = GL_NEAREST_MIPMAP_LINEAR;
    }
    else if (filterMode == 4){
        _filterMode = GL_LINEAR_MIPMAP_LINEAR;
    }
    else {
        _filterMode = GL_NEAREST_MIPMAP_NEAREST;
    }
    
    [self setTextureParameter];

    [self render];
}

@end
