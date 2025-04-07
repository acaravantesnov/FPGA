--=================================================================================================
-- Title       : FSM
-- File        : fsm_rtl.vhd
-- Description : Finite State Machine that controls flow of data through the PUF.
--
--               The FSM itself is as follows (states and transitions):
--
--               - IDLE:
--
--                 The FSM reaches this state as soon as the main reset of the system is activated
--                 (reset_n). During this state, the FSM waits for the lfsr sub-PUF to generate the
--                 seed of the LFSR through the comparison of c_lfsr_width * 2 Ring Oscillators, as
--                 defined in ring_oscillator_puf top design file.
--
--               - REG_SEED:
--
--                 Once the seed is genarated by the lfsr_seed_inst (lfsr_seed_value_ready
--                 indicating the FSM), the FSM registers the seed value from the lfsr_seed_inst
--                 into the lfsr_inst through reg_lfsr_seed signal as a single pulse.
--
--               - SEED_READY:
--
--                 On the next clk cycle, the FSM enters the SEED_READY state, where it resets the
--                 lfsr_inst initial value with the seed, the comparator_inst zeroing both counters
--                 and timer, and the fifo_inst through a single active pulse of fsm_reset_n signal.
--
--               - ONE_BIT:
--
--                 On the next clk cycle, the FSM enters the ONE_BIT state. Here, it gives a single
--                 clk pulse to the lfsr_inst through lfsr_clk. This generates a new value, which
--                 will indicate the pair of ROs from the main sub-PUF to compare.
--
--                 At this moment, the FSM needs to give the system several clk cycles to:
--
--                 x Allow for combinational logic to generate the lfsr value and map the RO clks.
--                 x Wait for the whole timer count up to g_timer_comparator_eoc value, when both
--                   counter values are compared.
--
--                 To do so, the FSM waits for the triggering of comparator_value_ready signal from
--                 comparator_inst, which indicates that a new value has been loaded to the fifo
--                 (as this same signal is fed into the clk of the fifo).
--
--!                Something to check is if the fifo is able to detect through rising_edge(clk)
--!                the edge of the comparator_value_ready signal.
--
--                 If apart from this signal, the FSM detects the fifo_full signal as active
--                 (high), the FSM goes to the REG_FIFO state, where it register the fifo value to
--                 the response output, and set high the ready flag for a single clk cycle.
--                 Otherwise, it means that a new value has been loaded into the fifo but it is
--                 not full yet. Therefore, the FSM enters the ONE_BIT state again, to generate a
--                 new lfsr value, and compare two different RO clks.
--
--                 The ONE_BIT state should also reset comparator_inst, as its timer has reached
--                 its maximum value after previous comparison. Therefore, another aux reset signal
--                 is added, comparison_reset_n (aux_2_reset_n for comparison_inst).
--
--!                Another thing to check is if entering ONE_BIT state again, the lfsr_clk
--!                signal will be triggered again (I doubt it).
--
--               - REG_FIFO:
--
--                 As mentioned before, the REG_FIFO state registers the fifo value onto response
--                 output and sets high the ready flag during a single clk cycle.
--
--                 After this, on the next clk cycle, the FSM enters the SEED_READY state again,
--                 where it will reset the subsystems and do the same process again.
--
-- Generics    : g_reset_polarity   -> Active high ('1') or active low ('0') rest for both reset_n
--                                     and fsm_reset_n.
-- Author      : Alberto Caravantes Arranz
-- Date        : 06/04/2025
-- Version     : 1.0
--=================================================================================================

-- Revision History:
-- Version 1.0 - Initial version

library ieee;
use ieee.std_logic_1164.all;

entity fsm is
    generic(
        g_reset_polarity : std_logic := '0'
    );
    port(
        -- Global signals
        reset_n                 : in std_logic;
        clk                     : in std_logic;

        -- LFSR seed ready signal from seed module
        lfsr_seed_value_ready   : in std_logic;

        -- Register to store seed value
        reg_lfsr_seed           : out std_logic;

        -- LFSR module control
        lfsr_clk                : out std_logic;

        -- Comparator control
        comparator_value_ready_d: in std_logic;

        -- FIFO control and status
        fifo_full               : in std_logic;

        -- Register trigger for FIFO
        reg_fifo_enable         : out std_logic;

        -- Control Reset
        fsm_reset_n             : out std_logic;
        comparison_reset_n      : out std_logic
    );
end entity fsm;

architecture rtl of fsm is

    -- Define FSM states
    type t_state is (IDLE, REG_SEED, SEED_READY, ONE_BIT, REG_FIFO);
    signal current_state : t_state;
    signal next_state    : t_state;
    
begin

    STATE_REGISTER: process(reset_n, clk)
    begin
        if (reset_n = g_reset_polarity) then
            current_state <= IDLE;
        elsif (rising_edge(clk)) then
            current_state <= next_state;
        end if;
    end process STATE_REGISTER;

    STATE_TRANSITION: process(current_state)
    begin
        next_state <= current_state;

        case current_state is
            when IDLE =>
                if (lfsr_seed_value_ready = '1') then
                    next_state <= REG_SEED;
                end if;
            when REG_SEED =>
                next_state <= SEED_READY;
            when SEED_READY =>
                next_state <= ONE_BIT;
            when ONE_BIT =>
                if (comparator_value_ready_d = '1') then
                    if (fifo_full = '0') then
                        next_state <= ONE_BIT; -- Will it trigger a pulse of lfsr_clk_i again?
                    else
                        next_state <= REG_FIFO;
                    end if;
                end if;
            when REG_FIFO =>
                next_state <= SEED_READY;
            when others => 
        end case;
    end process STATE_TRANSITION;

    OUTPUT: process(current_state)
    begin
        reg_lfsr_seed <= '0';
        lfsr_clk <= '0';
        reg_fifo_enable <= '0';
        fsm_reset_n <= '1';
        comparison_reset_n <= '1';

        case current_state is
            when SEED_READY =>
                fsm_reset_n <= '0';
            when REG_SEED =>
                reg_lfsr_seed <= '1';
            when ONE_BIT =>
                lfsr_clk <= '1';
                comparison_reset_n <= '0';
            when REG_FIFO =>
                reg_fifo_enable <= '1';
            when others =>
                null;
        end case;
    end process OUTPUT;

end architecture rtl;
