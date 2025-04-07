--=================================================================================================
-- Title       : Ring Oscillator PUF
-- File        : ring_oscillator_puf_rtl.vhd
-- Description : Custom Physical Unclonnable Function without challenge, and a fixed response.
--
--               There are four main subsystems within the PUF:
--
--               - 1. Main sub-PUF and combinational clock pair mapping: Array of Ring Oscillators
--                    whose clock signals will be compared to generate a response at the output.
--               - 2. LFSR sub-PUF and LFSR: Array of Ring Oscillators whose clock signal
--                    comparison serves as the seed for the LFSR.
--               
--                    For each LFSR value after the seed, the mapping combinational process maps
--                    LFSR values to pairs of clocks from the main sub-PUF.
--
--               - 3. Main comparator, FIFO, and output register: After the mapping of 2 clk
--                    signals from the main sub-puf and paired given a lfsr value, the
--                    comparator_inst unit determines which RO clk signal is faster, and generates
--                    a single bit to decide the winner. The bit is storeed into the FIFO.
--                    Once the FIFO is full, its g_response_width width value is registered as the
--                    ouput response.
--
--               - 4. FSM: Coordinates the flow of data (seed - lfsr - comparator - FIFO - output
--                    register). Apart from the output response, the FSM generates a ready flag
--                    that is held of a single clk cycle and indicates the value is ready to be
--                    fetched from the output.
--
-- Generics    : g_timer_lfsr_seed_eoc  -> Number of clk cycles to wait until comparator within
--                                         lfsr_seed_inst makes the comparison between counters.
--               g_timer_comparator_eoc -> Number of clk cycles to wait until comparator within
--                                         comparator_inst makes the comparison between counters.
--               g_n_inverters_main     -> Number of inverters per RO in the main RO array.
--               g_n_ROs_main           -> Number of Ring Oscillators in the main RO array.
--               g_n_inverters_lfsr     -> Number of inverters per RO in the lfsr RO array.
--               g_lfsr_polynomial      -> Coefficients of the polynomial to be applied in the
--                                         lfsr_inst.
--               g_response_width       -> Output response width of the PUF.
--               g_reset_polarity       -> Active high ('1') or active low ('0') rest for both
--                                         reset_n and fsm_reset_n_i within the PUF.
-- Author      : Alberto Caravantes Arranz
-- Date        : 06/04/2025
-- Version     : 1.0
--=================================================================================================

-- Revision History:
-- Version 1.0 - Initial version

library ieee;
use ieee.std_logic_1164.all;

use work.aux_pkg.all;

entity ring_oscillator_puf is
    generic(
        g_timer_lfsr_seed_eoc   : natural := 100E3;
        g_timer_comparator_eoc  : natural := 100E3;
        g_n_inverters_main      : natural := 5;
        g_n_ROs_main            : natural := 8;
        g_n_inverters_lfsr      : natural := 5;
        g_lfsr_polynomial       : natural := 20;
        g_response_width        : natural := 8;
        g_reset_polarity        : std_logic := '0'
    );
    port(
        clk     : in  std_logic;
        reset_n : in  std_logic;
        enable  : in std_logic;
        response: out std_logic_vector(g_response_width - 1 downto 0);
        ready   : out std_logic
    );
end entity ring_oscillator_puf;

architecture rtl of ring_oscillator_puf is

    -----------------------------------------------------------------------------------------------
    -- Constants
    -----------------------------------------------------------------------------------------------

    constant c_RO_main_combinations: natural := (g_n_ROs_main * (g_n_ROs_main - 1)) / 2;
    constant c_lfsr_width: natural := ceil_log2(c_RO_main_combinations);

    -----------------------------------------------------------------------------------------------
    -- Internal Signals
    -----------------------------------------------------------------------------------------------

    -- Ring Oscillator Units
    signal RO_unit_main_clks_i: std_logic_vector(g_n_ROs_main - 1 downto 0);
    signal RO_unit_lfsr_clks_i: std_logic_vector((c_lfsr_width * 2) - 1 downto 0);

    -- LFSR
    signal lfsr_seed_i: std_logic_vector(c_lfsr_width - 1 downto 0);
    signal lfsr_seed_i_d: std_logic_vector(c_lfsr_width - 1 downto 0);
    signal lfsr_seed_value_ready_i: std_logic;
    signal lfsr_reset_n_i: std_logic;
    signal lfsr_i: natural;

    -- Map
    type natural_array is array (natural range <>) of natural;
    signal map_index: natural_array(1 downto 0);
    --
    signal map_out_i: std_logic_vector(1 downto 0);

    -- Comparator
    signal comparator_result_i: std_logic_vector(0 downto 0);
    signal comparator_value_ready_i: std_logic;
    signal comparator_value_ready_i_d: std_logic;

    -- FIFO
    signal fifo_i: std_logic_vector(g_response_width - 1 downto 0);
    signal fifo_full_i: std_logic;

    -- FSM
    signal fsm_reset_n_i: std_logic;
    signal comparison_reset_n_i: std_logic;
    signal reg_lfsr_seed_i: std_logic;
    signal lfsr_clk_i: std_logic;

    -- Output Register
    signal fifo_i_d: std_logic_vector(g_response_width - 1 downto 0);
    signal reg_fifo_i: std_logic;
    signal reg_fifo_i_d: std_logic;

    -----------------------------------------------------------------------------------------------
    -- Component Declarations
    -----------------------------------------------------------------------------------------------

    component ring_oscillator is
        generic(
            g_n_inverters: natural := 5
        );
        port(
            enable  : in  std_logic;
            clk_out : out std_logic
        );
    end component ring_oscillator;

    component comparator is
        generic(
            g_input_width   : natural := 10;
            g_timer_eoc     : natural := 100E3;
            g_reset_polarity: std_logic := '0'
        );
        port(
            clk                 : in std_logic;
            aux_reset_n         : in std_logic;
            aux_2_reset_n       : in std_logic;
            reset_n             : in std_logic; -- Resets Counters and Timer, generated by FSM in lfsr_seed_inst, by input in comparator_inst
            RO_clks             : in std_logic_vector(g_input_width - 1 downto 0);
            comparison_result   : out std_logic_vector((g_input_width / 2) - 1 downto 0);
            value_ready         : out std_logic
        );
    end component comparator;

    component lfsr is
        generic(
            g_width             : natural := 5;
            g_polynomial        : natural := 20;
            g_reset_polarity    : std_logic := '0'
        );
        port(
            lfsr_clk    : in  std_logic;
            aux_reset_n : in std_logic;
            reset_n     : in  std_logic;
            seed        : in  std_logic_vector(g_width - 1 downto 0);
            lfsr        : out natural
        );
    end component lfsr;

    component fifo is
        generic(
            g_width         : natural range 2 to 16 := 8;
            g_reset_polarity: std_logic := '0'
        );
        port(
            clk         : in std_logic;
            aux_reset_n : in std_logic;
            reset_n     : in std_logic;
            input_value : in std_logic;
            output_value: out std_logic_vector(g_width - 1 downto 0);
            fifo_full   : out std_logic
        );
    end component fifo;

    component fsm is
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
    end component fsm;

begin

    -----------------------------------------------------------------------------------------------
    -- Ring Oscillator Unit \(main\)
    -----------------------------------------------------------------------------------------------
    --
    -----------------------------------------------------------------------------------------------
    GEN_ROS_MAIN: for i in 0 to g_n_ROs_main - 1 generate
        RO_inst: Ring_Oscillator
            generic map(
                g_n_inverters => g_n_inverters_main
            )
            port map(
                enable  => enable,
                clk_out => RO_unit_main_clks_i(i)
            );
    end generate GEN_ROS_MAIN;

    -----------------------------------------------------------------------------------------------
    -- Ring Oscillator Unit \(lfsr\)
    -----------------------------------------------------------------------------------------------
    --
    -----------------------------------------------------------------------------------------------
    GEN_ROS_LFSR: for i in 0 to (c_lfsr_width * 2) - 1 generate
        RO_inst: Ring_Oscillator
            generic map(
                g_n_inverters => g_n_inverters_lfsr
            )
            port map(
                enable  => '1',
                clk_out => RO_unit_lfsr_clks_i(i)
            );
    end generate GEN_ROS_LFSR;

    -----------------------------------------------------------------------------------------------
    -- LFSR Seed
    -----------------------------------------------------------------------------------------------
    --
    -----------------------------------------------------------------------------------------------
    lfsr_seed_inst: comparator
        generic map(
            g_input_width => c_lfsr_width * 2,
            g_timer_eoc => g_timer_lfsr_seed_eoc,
            g_reset_polarity => g_reset_polarity
        )
        port map(
            clk => clk,
            aux_reset_n => not g_reset_polarity,
            aux_2_reset_n => not g_reset_polarity,
            reset_n => reset_n,
            RO_clks => RO_unit_lfsr_clks_i,
            comparison_result => lfsr_seed_i,
            value_ready => lfsr_seed_value_ready_i
        );

    REG_LFSR_SEED: process(reset_n, clk)
    begin
        if (reset_n = g_reset_polarity) then
            lfsr_seed_i_d <= (others => '0');
        elsif (rising_edge(clk)) then
            if (reg_lfsr_seed_i = '1') then
                lfsr_seed_i_d <= lfsr_seed_i;
            end if;
        end if;
    end process REG_LFSR_SEED;

    -----------------------------------------------------------------------------------------------
    -- LFSR
    -----------------------------------------------------------------------------------------------
    --
    -----------------------------------------------------------------------------------------------
    lfsr_inst: lfsr
        generic map(
            g_width => c_lfsr_width,
            g_polynomial => g_lfsr_polynomial,
            g_reset_polarity => g_reset_polarity
        )
        port map(
            lfsr_clk => lfsr_clk_i,
            aux_reset_n => fsm_reset_n_i,
            reset_n => reset_n,
            seed => lfsr_seed_i_d,
            lfsr => lfsr_i
        );

    -----------------------------------------------------------------------------------------------
    -- RO Clock Pair Mapping
    -----------------------------------------------------------------------------------------------
    --
    -----------------------------------------------------------------------------------------------
    proc_map: process(lfsr_i)
        variable i, j: natural := 0;
        variable k: natural := lfsr_i;
    begin
        for idx in 0 to g_n_ROs_main-2 loop  -- worst-case bound
            exit when k < (g_n_ROs_main - idx - 1);
            k := k - (g_n_ROs_main - idx - 1);
            i := i + 1;
        end loop;
        j := i + 1 + k;
        map_index(0) <= i;
        map_index(1) <= j;
    end process;

    map_out_i(0) <= RO_unit_main_clks_i(map_index(0));
    map_out_i(1) <= RO_unit_main_clks_i(map_index(1));

    -----------------------------------------------------------------------------------------------
    -- Comparator Unit
    -----------------------------------------------------------------------------------------------
    --
    -----------------------------------------------------------------------------------------------
    comparator_inst: comparator
        generic map(
            g_input_width => 2,
            g_timer_eoc => g_timer_comparator_eoc,
            g_reset_polarity => g_reset_polarity
        )
        port map(
            clk => clk,
            aux_reset_n => fsm_reset_n_i,
            aux_2_reset_n => comparison_reset_n_i,
            reset_n => reset_n,
            RO_clks => map_out_i,
            comparison_result => comparator_result_i,
            value_ready => comparator_value_ready_i
        );

    process(reset_n, clk)
    begin
        if (reset_n = g_reset_polarity) then
            comparator_value_ready_i_d <= '0';
        elsif (rising_edge(clk)) then
            comparator_value_ready_i_d <= comparator_value_ready_i;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- 1-bit FIFO
    -----------------------------------------------------------------------------------------------
    --
    -----------------------------------------------------------------------------------------------
    fifo_inst: fifo
        generic map(
            g_width => g_response_width,
            g_reset_polarity => g_reset_polarity
        )
        port map(
            clk => comparator_value_ready_i, -- FIFO should be able to detect just the rising_edge of the signal.
            aux_reset_n => fsm_reset_n_i,
            reset_n => reset_n,
            input_value => comparator_result_i(0),
            output_value => fifo_i,
            fifo_full => fifo_full_i
        );

    -----------------------------------------------------------------------------------------------
    -- FSM
    -----------------------------------------------------------------------------------------------
    --
    -----------------------------------------------------------------------------------------------
    fsm_inst: fsm
        generic map(
            g_reset_polarity => g_reset_polarity
        )
        port map(
            -- Global signals
            reset_n => reset_n,
            clk => clk,

            -- LFSR seed ready signal from seed module
            lfsr_seed_value_ready => lfsr_seed_value_ready_i,

            -- Register to store seed value
            reg_lfsr_seed => reg_lfsr_seed_i,

            -- LFSR module control
            lfsr_clk => lfsr_clk_i,

            -- Comparator control
            comparator_value_ready_d => comparator_value_ready_i_d,

            -- FIFO control and status
            fifo_full => fifo_full_i,

            -- Register trigger for FIFO
            reg_fifo_enable => reg_fifo_i,

            -- Control Reset
            fsm_reset_n => fsm_reset_n_i,
            comparison_reset_n => comparison_reset_n_i
        );

    -----------------------------------------------------------------------------------------------
    -- Output register
    -----------------------------------------------------------------------------------------------
    --
    -----------------------------------------------------------------------------------------------
    process(reset_n, clk)
    begin
        if ((reset_n = g_reset_polarity) or (fsm_reset_n_i = g_reset_polarity)) then
            fifo_i_d <= (others => '0');
            reg_fifo_i_d <= '0';
        elsif rising_edge(clk) then
            reg_fifo_i_d <= reg_fifo_i;
            
            if ((reg_fifo_i_d = '0') and (reg_fifo_i = '1')) then
                fifo_i_d <= fifo_i;
            end if;
        end if;
    end process;

    ready <= reg_fifo_i;

end architecture rtl;
