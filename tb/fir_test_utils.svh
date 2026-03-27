`define FIR_RESIZE_AND_SATURATE_FN \
function automatic sample_t resize_and_saturate(input acc_t value); \
    acc_t rounded; \
    acc_t shifted; \
    begin \
        if (FIR_COEFF_FRAC_BITS > 0) begin \
            if (value >= 0) begin \
                rounded = value + ({{(ACC_WIDTH-1){1'b0}}, 1'b1} <<< (FIR_COEFF_FRAC_BITS - 1)); \
            end else begin \
                rounded = value - ({{(ACC_WIDTH-1){1'b0}}, 1'b1} <<< (FIR_COEFF_FRAC_BITS - 1)); \
            end \
            shifted = rounded >>> FIR_COEFF_FRAC_BITS; \
        end else begin \
            shifted = value; \
        end \
        if (shifted > SAMPLE_MAX_EXT) begin \
            resize_and_saturate = SAMPLE_MAX; \
        end else if (shifted < SAMPLE_MIN_EXT) begin \
            resize_and_saturate = SAMPLE_MIN; \
        end else begin \
            resize_and_saturate = shifted[SAMPLE_WIDTH-1:0]; \
        end \
    end \
endfunction

`define FIR_RANDOM_SAMPLE_FN \
function automatic sample_t random_sample(input int sample_idx); \
    logic [31:0] state; \
    integer iter; \
    begin \
        state = 32'h1badf00d; \
        for (iter = 0; iter <= sample_idx; iter++) begin \
            state = (state * 32'd1664525) + 32'd1013904223; \
        end \
        random_sample = sample_t'(state[15:0]); \
    end \
endfunction

`define FIR_SINE_SAMPLE_FN \
function automatic sample_t sine_sample( \
    input int sample_idx, \
    input real amplitude, \
    input real period_samples \
); \
    real angle; \
    integer value; \
    begin \
        angle = 2.0 * 3.14159265358979323846 * sample_idx / period_samples; \
        value = $rtoi(amplitude * $sin(angle)); \
        sine_sample = sample_t'(value); \
    end \
endfunction

`define FIR_HISTORY_RESET(history_arr) \
    begin \
        for (score_idx = 0; score_idx < FIR_NUM_TAPS; score_idx++) begin \
            history_arr[score_idx] = '0; \
        end \
    end

`define FIR_HISTORY_PUSH(history_arr, new_sample) \
    begin \
        for (score_idx = FIR_NUM_TAPS - 1; score_idx > 0; score_idx--) begin \
            history_arr[score_idx] = history_arr[score_idx - 1]; \
        end \
        history_arr[0] = new_sample; \
    end

`define FIR_SCALAR_EXPECT(expected_var, history_arr, new_sample) \
    begin \
        sample_t model_next [0:FIR_NUM_TAPS-1]; \
        acc_t acc_tmp; \
        integer model_idx; \
        model_next[0] = new_sample; \
        for (model_idx = 1; model_idx < FIR_NUM_TAPS; model_idx++) begin \
            model_next[model_idx] = history_arr[model_idx - 1]; \
        end \
        acc_tmp = '0; \
        for (model_idx = 0; model_idx < FIR_NUM_TAPS; model_idx++) begin \
            acc_tmp = acc_tmp + (model_next[model_idx] * fir_coeff(model_idx)); \
        end \
        expected_var = resize_and_saturate(acc_tmp); \
    end
