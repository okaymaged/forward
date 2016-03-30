#define TANH 1

// expected defines:
// one of: [ TANH | RELU | LINEAR | SIGMOID | SCALEDTANH | ELU ]
#ifdef TANH
    #define ACTIVATION_FUNCTION(output) (tanh(output))
#elif defined SCALEDTANH
    #define ACTIVATION_FUNCTION(output) (1.7159f * tanh(0.66667f * output))
#elif SIGMOID
    #define ACTIVATION_FUNCTION(output) (1.0f / (1 + exp(-output)))
#elif defined RELU
    #define ACTIVATION_FUNCTION(output) (output> 0 ? output : 0)
#elif defined ELU
    #define ACTIVATION_FUNCTION(output) (output> 0 ? output : exp(output) - 1)
#elif defined LINEAR
    #define ACTIVATION_FUNCTION(output) (output)
#endif

#ifdef ACTIVATION_FUNCTION // protect against not defined
__attribute__((num_simd_work_items(4)))
__attribute__((reqd_work_group_size(1024,1,1)))
kernel void forwardNaive(global float * restrict out, global const float * restrict in) {
    const int globalId = get_global_id(0);
    out[globalId] = ACTIVATION_FUNCTION(in[globalId]);
}
#endif

void kernel convolve_imagecubes_float2(
    const int numExamples,
    global const float * restrict inputs, 
    global const float * restrict filters, 
    global float * restrict output, 
    const int isFirstTime) {

    int globalId = get_global_id(0);

    const int gInputSizeSquared = 1024;
    const int gInputSize = 32;
    int gHalfFilterSize;
    int gEven;
    int gNumFilters;
    int gOutputSize;
    int gNumInputPlanes;
    int gFilterSize;
    int gFilterSizeSquared;
    int gPadZeros;

    if (isFirstTime) {
    	gHalfFilterSize = 2;
    	gEven = 0;
    	gNumFilters = 8;
    	gOutputSize = 32;
    	gNumInputPlanes = 1;
    	gFilterSize = 5;
    	gFilterSizeSquared = 25;
    	gPadZeros = 1;
    } else {
    	gHalfFilterSize = 16;
    	gEven = 1;
    	gNumFilters = 7;
    	gOutputSize = 1;
    	gNumInputPlanes = 8;
    	gFilterSize = 32;
    	gFilterSizeSquared = 1024;
    	gPadZeros = 0;
    }

    int outputImage2Id = isFirstTime ? globalId >> 10 : globalId;
    int exampleId = outputImage2Id >> 3;
    int filterId = outputImage2Id & 0b111;

    // intraimage coords
    int localid = isFirstTime ? globalId & 0b1111111111 : 0;
    int outputRow = isFirstTime ? localid >> 5 : localid;
    int outputCol = isFirstTime ? localid & 0b11111 : 0;

    global float const*inputCube = inputs + exampleId * gNumInputPlanes * gInputSizeSquared;
    global float const*filterCube = filters + filterId * gNumInputPlanes * gFilterSizeSquared;


    float sum = 0;
    if (exampleId < numExamples) {
        for (int inputPlaneIdx = 0; inputPlaneIdx < gNumInputPlanes; inputPlaneIdx++) {
            global float const*inputPlane = inputCube + inputPlaneIdx * gInputSizeSquared;
            global float const*filterPlane = filterCube + inputPlaneIdx * gFilterSizeSquared;
            for (int u = -gHalfFilterSize; u <= gHalfFilterSize - gEven; u++) {
                // trying to reduce register pressure...
		int inputRowIdx = outputRow + u;
		if (!gPadZeros) {
			inputRowIdx += gHalfFilterSize;
		}
                global float const *inputRow = inputPlane + inputRowIdx * gInputSize;
                global float const *filterRow = filterPlane + (u+gHalfFilterSize) * gFilterSize + gHalfFilterSize;
                bool rowOk = inputRowIdx >= 0 && inputRowIdx < gInputSize;
                #pragma unroll
                for (int v = -gHalfFilterSize; v <= gHalfFilterSize - gEven; v++) {
		    int inputColIdx;
		    if (gPadZeros) {
			inputColIdx = (outputCol + v);
		    } else {
			inputColIdx = (outputCol + v + gHalfFilterSize);
		    }
                    bool process = rowOk && inputColIdx >= 0 && inputColIdx < gInputSize;
                    if (process) {
                            sum += inputRow[inputColIdx] * filterRow[v];
                    }
                }
            }
        }
    }

    if (exampleId < numExamples) {
        output[globalId] = sum;
    }
}

__attribute__((num_compute_units(2)))
__attribute__((num_simd_work_items(4)))
__attribute__((reqd_work_group_size(64,1,1)))
kernel void repeated_add1(global float * restrict target, global const float * restrict source) {
    const int globalId = get_global_id(0);
    target[globalId] += source[ (globalId >> 10) & 0b111 ];
}

__attribute__((reqd_work_group_size(64,1,1)))
kernel void repeated_add2(global float * restrict target, global const float * restrict source) {
    const int globalId = get_global_id(0);
    target[globalId] += source[ globalId & 0b111 ];
}
