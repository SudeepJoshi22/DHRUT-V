<!-- Improved compatibility of back to top link: See: https://github.com/othneildrew/Best-README-Template/pull/73 -->
<a name="readme-top"></a>
<!--
*** Thanks for checking out the Best-README-Template. If you have a suggestion
*** that would make this better, please fork the repo and create a pull request
*** or simply open an issue with the tag "enhancement".
*** Don't forget to give the project a star!
*** Thanks again! Now go create something AMAZING! :D
-->



<!-- PROJECT SHIELDS -->
<!--
*** I'm using markdown "reference style" links for readability.
*** Reference links are enclosed in brackets [ ] instead of parentheses ( ).
*** See the bottom of this document for the declaration of the reference variables
*** for contributors-url, forks-url, etc. This is an optional, concise syntax you may use.
*** https://www.markdownguide.org/basic-syntax/#reference-style-links
-->
[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![MIT License][license-shield]][license-url]
[![LinkedIn][linkedin-shield]][linkedin-url]



<!-- PROJECT LOGO -->
<br />
<div align="center">
  <a href="https://github.com/SudeepJoshi22/DHRUT-V">
    <img src="logo.jpeg" alt="Logo" width="180" height="180">
  </a>

<h3 align="center">DHRUT-V</h3>

  <p align="center">
    Custom Designed RISC-V core for educational and learning purpose
    <br />
    <a href="https://github.com/SudeepJoshi22/DHRUT-V"><strong>Explore the docs »</strong></a>
    <br />
    <br />
    <a href="https://github.com/SudeepJoshi22/DHRUT-V">View Demo</a>
    ·
    <a href="https://github.com/SudeepJoshi22/DHRUT-V/issues">Report Bug</a>
    ·
    <a href="https://github.com/SudeepJoshi22/DHRUT-V/issues">Request Feature</a>
  </p>
</div>



<!-- TABLE OF CONTENTS -->
<details>
  <summary>Table of Contents</summary>
  <ol>
    <li>
      <a href="#about-the-project">About The Project</a>
      <ul>
        <li><a href="#built-with">Built With</a></li>
      </ul>
    </li>
    <li>
      <a href="#getting-started">Getting Started</a>
      <ul>
        <li><a href="#prerequisites">Prerequisites</a></li>
        <li><a href="#installation">Installation</a></li>
      </ul>
    </li>
    <li><a href="#usage">Usage</a></li>
    <li><a href="#roadmap">Roadmap</a></li>
    <li><a href="#contributing">Contributing</a></li>
    <li><a href="#license">License</a></li>
    <li><a href="#contact">Contact</a></li>
    <li><a href="#acknowledgments">Acknowledgments</a></li>
  </ol>
</details>



<!-- ABOUT THE PROJECT -->
## About The Project

<!--
[![Product Name Screen Shot][product-screenshot]](https://example.com)
-->

This is a custom designed RISC-V core, fouced on easy understading of the RISC-V ISA, RISC-V microarchitecture design and verified using open-source and RISC-V tool chains.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



### Designed and Verified with

* ![Verilog][verilog-hdl]
* ![RISC-V][riscv-hdl]

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- GETTING STARTED -->
## Getting Started

The project uses riscv-gcc cross-compiler to compile and link the tests. Spike simulator as the Instruction Set Simulator. The verilog files are compiled using iverilog and waveform is run using gtkwave tool.
(lint checking and formal verification yet to be added, verilator and symbi-yosys to be used). Makefile has been used to run different tasks and install toolchains.
 
### Install toolchains

 ```sh
 make init
 ```


### Simulating a program on the core and Spike

1. This will take the program ![test.S](https://github.com/SudeepJoshi22/DHRUT-V/blob/main/programs/test.S) as the default program to run on the core
 ```sh
 make core
 ```
2. To run your own custom program on the core
 ```sh
 make core TEST_PROGRAM=<your_test_name>
 ```
3. To run a single verilog file(test bench should be in ![test_bench](https://github.com/SudeepJoshi22/DHRUT-V/tree/main/test_bench) and verilog design should be in ![rtl](https://github.com/SudeepJoshi22/DHRUT-V/tree/main/rtl)
 ```sh
 make compile TB=<test_bench_name> DESIGN=<module_name>
 ```
<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- USAGE EXAMPLES 
## Usage

Use this space to show useful examples of how a project can be used. Additional screenshots, code examples and demos work well in this space. You may also link to more resources.

_For more examples, please refer to the [Documentation](https://example.com)_

<p align="right">(<a href="#readme-top">back to top</a>)</p>

-->

<!-- ROADMAP -->
## Roadmap

- [ ] Pipeline the Core
- [ ] Add CSR Features
- [ ] Run RISC-V Compitability tests
- [ ] Add Coverage Features, Formal Verification and Lint checks
- [ ] Synthesize and Run on FPGA

See the [open issues](https://github.com/SudeepJoshi22/DHRUT-V) for a full list of proposed features (and known issues).

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- CONTRIBUTING 
## Contributing

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

If you have a suggestion that would make this better, please fork the repo and create a pull request. You can also simply open an issue with the tag "enhancement".
Don't forget to give the project a star! Thanks again!

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

<p align="right">(<a href="#readme-top">back to top</a>)</p>

-->

<!-- LICENSE -->
## License

Distributed under the Apache License 2.0. See `LICENSE.txt` for more information.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- CONTACT -->
## Project Creator

Sudeep Joshi - sudeepj881@gmail.com

Project Link: [https://github.com/SudeepJoshi22/DHRUT-V](https://github.com/SudeepJoshi22/DHRUT-V)

<p align="right">(<a href="#readme-top">back to top</a>)</p>


<!-- CONTRIBUTORS -->
## Contributors

<name> - <email>

Profile : [social handle](www.example.com)

<p align="right">(<a href="#readme-top">back to top</a>)</p>


<!-- ACKNOWLEDGMENTS 
## Acknowledgments

* []()
* []()
* []()

<p align="right">(<a href="#readme-top">back to top</a>)</p>

-->

<!-- MARKDOWN LINKS & IMAGES -->
<!-- https://www.markdownguide.org/basic-syntax/#reference-style-links -->
[contributors-shield]: https://img.shields.io/github/contributors/SudeepJoshi22/DHRUT-V.svg?style=for-the-badge
[contributors-url]: https://github.com/SudeepJoshi22/DHRUT-V/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/SudeepJoshi22/DHRUT-V.svg?style=for-the-badge
[forks-url]: https://github.com/SudeepJoshi22/DHRUT-V/network/members
[stars-shield]: https://img.shields.io/github/stars/SudeepJoshi22/DHRUT-V.svg?style=for-the-badge
[stars-url]: https://github.com/SudeepJoshi22/DHRUT-V/stargazers
[issues-shield]: https://img.shields.io/github/issues/SudeepJoshi22/DHRUT-V.svg?style=for-the-badge
[issues-url]: https://github.com/SudeepJoshi22/DHRUT-V/issues
[license-shield]: https://img.shields.io/github/license/SudeepJoshi22/DHRUT-V.svg?style=for-the-badge
[license-url]: https://github.com/SudeepJoshi22/DHRUT-V/blob/master/LICENSE.txt
[linkedin-shield]: https://img.shields.io/badge/-LinkedIn-black.svg?style=for-the-badge&logo=linkedin&colorB=555
[linkedin-url]: https://linkedin.com/in/linkedin_username
[product-screenshot]: images/screenshot.png
[Next.js]: https://img.shields.io/badge/next.js-000000?style=for-the-badge&logo=nextdotjs&logoColor=white
[Next-url]: https://nextjs.org/
[React.js]: https://img.shields.io/badge/React-20232A?style=for-the-badge&logo=react&logoColor=61DAFB
[React-url]: https://reactjs.org/
[Vue.js]: https://img.shields.io/badge/Vue.js-35495E?style=for-the-badge&logo=vuedotjs&logoColor=4FC08D
[Vue-url]: https://vuejs.org/
[Angular.io]: https://img.shields.io/badge/Angular-DD0031?style=for-the-badge&logo=angular&logoColor=white
[Angular-url]: https://angular.io/
[Svelte.dev]: https://img.shields.io/badge/Svelte-4A4A55?style=for-the-badge&logo=svelte&logoColor=FF3E00
[Svelte-url]: https://svelte.dev/
[Laravel.com]: https://img.shields.io/badge/Laravel-FF2D20?style=for-the-badge&logo=laravel&logoColor=white
[Laravel-url]: https://laravel.com
[Bootstrap.com]: https://img.shields.io/badge/Bootstrap-563D7C?style=for-the-badge&logo=bootstrap&logoColor=white
[Bootstrap-url]: https://getbootstrap.com
[JQuery.com]: https://img.shields.io/badge/jQuery-0769AD?style=for-the-badge&logo=jquery&logoColor=white
[JQuery-url]: https://jquery.com 

[verilog-url]: https://www.verilog.com/
[riscv-url]: https://riscv.org/
